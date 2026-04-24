// Pillar 6 — Rcpp port of the ZZFeatureMap quantum-kernel simulator
// (edaphos v2.1.3).
//
// Mathematical contract
// ---------------------
// For an n-qubit system the ZZFeatureMap of Havlicek et al. (2019)
// prepares
//
//     |phi(x)> = ( U_phi(x) H^{otimes n} )^R |0>^{otimes n}
//
// where U_phi(x) applies:
//   (i)  single-qubit rotations   Rz(2 x_i)  on every qubit i,
//   (ii) pairwise entangling      CNOT(i,j)  Rz( 2 (pi-x_i)(pi-x_j) )  CNOT(i,j)
//        for all i<j.
//
// The kernel is
//     K(x_i, x_j) = |<phi(x_j) | phi(x_i)>|^2
//
// This file implements the state-vector simulation in C++ for a ~10-50x
// speedup over the pure-R reference `quantum_kernel()` on n_samples
// beyond ~100.  The numerical output is identical to the R
// implementation up to machine precision (tested in
// `tests/testthat/test-quantum-kernel-rcpp.R`).
//
// Little-endian convention: qubit 0 is the LSB of the basis-state
// index i in [0, 2^n).

// [[Rcpp::plugins(cpp11)]]
#include <Rcpp.h>
#include <complex>
#include <cmath>
#include <vector>

typedef std::complex<double> cplx;
const double SQRT2_INV = 1.0 / std::sqrt(2.0);

// Apply a single-qubit gate given as a 2x2 matrix [[g00, g01], [g10, g11]]
// to qubit q of an n-qubit state stored as a length-2^n complex vector.
static inline void apply_single(std::vector<cplx>& state,
                                 cplx g00, cplx g01, cplx g10, cplx g11,
                                 int q) {
    const size_t mask = (size_t) 1 << q;
    const size_t dim  = state.size();
    // Iterate pairs where bit q is 0.
    for (size_t i = 0; i < dim; ++i) {
        if (i & mask) continue;
        const size_t j = i | mask;
        const cplx a = state[i];
        const cplx b = state[j];
        state[i] = g00 * a + g01 * b;
        state[j] = g10 * a + g11 * b;
    }
}

// Apply a Hadamard gate to qubit q.
static inline void apply_H(std::vector<cplx>& state, int q) {
    apply_single(state,
                  cplx(SQRT2_INV, 0),  cplx(SQRT2_INV,  0),
                  cplx(SQRT2_INV, 0),  cplx(-SQRT2_INV, 0), q);
}

// Apply an Rz(theta) = diag(exp(-i theta/2), exp(i theta/2)) gate.
static inline void apply_Rz(std::vector<cplx>& state, double theta, int q) {
    const cplx p0 = std::exp(cplx(0, -theta / 2.0));
    const cplx p1 = std::exp(cplx(0,  theta / 2.0));
    const size_t mask = (size_t) 1 << q;
    const size_t dim  = state.size();
    for (size_t i = 0; i < dim; ++i) {
        if (i & mask) state[i] *= p1;
        else          state[i] *= p0;
    }
}

// Apply a CNOT with control=c, target=t.  Swap amplitudes between
// index pairs (i, i XOR tmask) whenever the control bit of i is 1.
static inline void apply_CNOT(std::vector<cplx>& state, int control, int target) {
    const size_t cmask = (size_t) 1 << control;
    const size_t tmask = (size_t) 1 << target;
    const size_t dim   = state.size();
    for (size_t i = 0; i < dim; ++i) {
        if (!(i & cmask)) continue;      // control is 0
        const size_t j = i ^ tmask;
        if (j > i) std::swap(state[i], state[j]);
    }
}

// Compute |phi(x)> for the ZZFeatureMap and write it into state[0..2^n-1].
static void zz_feature_map(std::vector<cplx>& state,
                            const double* x, int n, int reps) {
    const size_t dim = state.size();
    // Initialise to |0...0>
    std::fill(state.begin(), state.end(), cplx(0, 0));
    state[0] = cplx(1, 0);

    for (int r = 0; r < reps; ++r) {
        // Hadamard layer
        for (int q = 0; q < n; ++q) apply_H(state, q);
        // Single-qubit phase rotations
        for (int q = 0; q < n; ++q) apply_Rz(state, 2.0 * x[q], q);
        // Entangling ZZ rotations for i<j
        if (n >= 2) {
            for (int i = 0; i < n - 1; ++i) {
                for (int j = i + 1; j < n; ++j) {
                    apply_CNOT(state, i, j);
                    const double phi_ij = 2.0 * (M_PI - x[i]) * (M_PI - x[j]);
                    apply_Rz(state, phi_ij, j);
                    apply_CNOT(state, i, j);
                }
            }
        }
    }
    // Suppress unused warning on `dim`
    (void) dim;
}

// [[Rcpp::export]]
Rcpp::NumericMatrix quantum_kernel_rcpp(Rcpp::NumericMatrix X,
                                          Rcpp::Nullable<Rcpp::NumericMatrix> Y_opt,
                                          int reps) {
    const int nX = X.nrow();
    const int n  = X.ncol();
    const bool same = Y_opt.isNull();

    Rcpp::NumericMatrix Ymat;
    if (!same) {
        Ymat = Rcpp::NumericMatrix(Y_opt);
        if (Ymat.ncol() != n) {
            Rcpp::stop("X and Y must have the same number of columns");
        }
    }
    const int nY = same ? nX : Ymat.nrow();

    if (n > 20) {
        Rcpp::warning("quantum_kernel_rcpp with n_qubits > 20 may exhaust RAM.");
    }
    const size_t dim = (size_t) 1 << n;

    // Pre-compute all X-states
    std::vector<std::vector<cplx>> states_X(nX, std::vector<cplx>(dim));
    std::vector<double> row_x(n);
    for (int i = 0; i < nX; ++i) {
        for (int k = 0; k < n; ++k) row_x[k] = X(i, k);
        zz_feature_map(states_X[i], row_x.data(), n, reps);
    }

    // Pre-compute Y-states (or share with X)
    std::vector<std::vector<cplx>>* states_Y_ptr;
    std::vector<std::vector<cplx>>  states_Y_storage;
    if (same) {
        states_Y_ptr = &states_X;
    } else {
        states_Y_storage.resize(nY, std::vector<cplx>(dim));
        for (int j = 0; j < nY; ++j) {
            for (int k = 0; k < n; ++k) row_x[k] = Ymat(j, k);
            zz_feature_map(states_Y_storage[j], row_x.data(), n, reps);
        }
        states_Y_ptr = &states_Y_storage;
    }

    // Inner products: K_{ij} = |<Y_j | X_i>|^2
    Rcpp::NumericMatrix K(nX, nY);
    for (int i = 0; i < nX; ++i) {
        const auto& si = states_X[i];
        const int j_start = same ? i : 0;
        for (int j = j_start; j < nY; ++j) {
            const auto& sj = (*states_Y_ptr)[j];
            cplx acc(0, 0);
            // acc = sum_k si[k] * conj(sj[k])
            for (size_t k = 0; k < dim; ++k) {
                acc += si[k] * std::conj(sj[k]);
            }
            const double val = std::norm(acc);   // |acc|^2
            K(i, j) = val;
            if (same && i != j) K(j, i) = val;   // symmetry
        }
    }

    // Numerical hygiene: clamp tiny negatives, enforce diag=1 when same set.
    if (same) {
        for (int i = 0; i < nX; ++i) K(i, i) = 1.0;
    }
    for (int i = 0; i < nX; ++i) {
        for (int j = 0; j < nY; ++j) {
            if (K(i, j) < 0) K(i, j) = 0;
        }
    }
    return K;
}
