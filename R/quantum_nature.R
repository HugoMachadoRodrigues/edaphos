# Pillar 6 -- qiskit-nature bridge to ab initio molecular Hamiltonians.
#
# The toy Hamiltonian shipped in R/quantum_vqe.R
# (quantum_hamiltonian_organo_mineral()) is a hand-built 4-qubit
# Pauli-string operator with arbitrary on-site energies and hoppings.
# It is useful as a pedagogical starting point but it is *not*
# quantum chemistry: there is no molecular geometry, no basis set,
# no electron-electron repulsion and no physically meaningful
# ground-state energy.
#
# This file wires an end-to-end pipeline from a user-supplied
# molecular geometry to a Pauli-string Hamiltonian that a VQE can
# minimise:
#
#       geometry (XYZ string)
#            |                (qiskit_nature.second_q.drivers.PySCFDriver)
#            v
#       ElectronicStructureProblem in the AO basis
#            |                (FreezeCoreTransformer, optional)
#            v
#       Frozen-core problem
#            |                (ActiveSpaceTransformer)
#            v
#       Reduced (n_e, n_o) active-space problem
#            |                (ParityMapper(num_particles) with
#            |                 inherent Z2 symmetry reduction)
#            v
#       SparsePauliOp   --->  edaphos_quantum_hamiltonian
#
# The bridge is self-contained: if qiskit-nature or pyscf are not
# installed, every public function emits a clear install-hint. All
# reticulate / Qiskit state lives in the `.qk_env` cache introduced
# by R/quantum_vqe.R.

# --- Python module loader ----------------------------------------------------

#' Check whether the qiskit-nature + PySCF stack is available
#'
#' Returns `TRUE` when (i) `reticulate` is installed; (ii) the
#' `qiskit` core module is importable; (iii) the `qiskit_nature`
#' Python module is importable; and (iv) the `pyscf` Python module
#' is importable. The function does not execute any electronic-
#' structure calculation — it is a cheap preflight probe safe to
#' call from tests and CI.
#'
#' @return Logical scalar.
#' @export
quantum_nature_available <- function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) return(FALSE)
  if (!reticulate::py_module_available("qiskit")) return(FALSE)
  if (!reticulate::py_module_available("qiskit_nature")) return(FALSE)
  if (!reticulate::py_module_available("pyscf")) return(FALSE)
  TRUE
}

.qn_require <- function() {
  .qk_require()
  if (!reticulate::py_module_available("qiskit_nature")) {
    stop("`qiskit_nature` Python module not found. Install once via\n",
         "   reticulate::py_install(c('qiskit-nature','pyscf'), ",
         "pip = TRUE)\n",
         "then restart R.", call. = FALSE)
  }
  if (!reticulate::py_module_available("pyscf")) {
    stop("`pyscf` Python module not found. Install once via\n",
         "   reticulate::py_install('pyscf', pip = TRUE)\n",
         "then restart R.", call. = FALSE)
  }
  if (is.null(.qk_env$qn_drivers)) {
    .qk_env$qn_drivers <- reticulate::import(
      "qiskit_nature.second_q.drivers", delay_load = FALSE
    )
    .qk_env$qn_mappers <- reticulate::import(
      "qiskit_nature.second_q.mappers", delay_load = FALSE
    )
    .qk_env$qn_transf <- reticulate::import(
      "qiskit_nature.second_q.transformers", delay_load = FALSE
    )
  }
  invisible(TRUE)
}

# --- core constructor --------------------------------------------------------

.qn_make_mapper <- function(name, num_particles) {
  name <- tolower(name)
  switch(
    name,
    parity        = .qk_env$qn_mappers$ParityMapper(
      num_particles = num_particles
    ),
    jordan_wigner = .qk_env$qn_mappers$JordanWignerMapper(),
    bravyi_kitaev = .qk_env$qn_mappers$BravyiKitaevMapper(),
    stop("Unknown mapper '", name, "'. Expected one of ",
         "'parity', 'jordan_wigner', 'bravyi_kitaev'.",
         call. = FALSE)
  )
}

.qn_sparsepauliop_to_list <- function(op) {
  # Qiskit's SparsePauliOp exposes `.paulis.to_labels()` (the Pauli
  # strings) and `.coeffs` (the complex coefficients). We convert the
  # full spec to a named numeric vector to drive
  # quantum_hamiltonian().
  strs   <- as.character(unlist(op$paulis$to_labels()))
  coeffs <- Re(as.complex(reticulate::py_to_r(op$coeffs)))
  stats::setNames(as.numeric(coeffs), strs)
}

#' Build a quantum Hamiltonian from a molecular geometry
#'
#' End-to-end ab initio pipeline:
#' 1. A restricted Hartree-Fock reference is computed by `PySCFDriver`
#'    in the requested atomic-orbital basis (STO-3G by default —
#'    minimal, illustrative, and small enough for laptop-scale VQE).
#' 2. Optionally, the chemical core orbitals are frozen out by
#'    `FreezeCoreTransformer` — a cheap and orbital-space-neutral
#'    reduction that typically halves the qubit count for first-row
#'    organics.
#' 3. The frontier orbitals are projected to an
#'    `(num_active_electrons, num_active_orbitals)` active space via
#'    `ActiveSpaceTransformer`, keeping the chemistry local to the
#'    coordination event the user cares about (e.g. Fe-O-C charge
#'    transfer in an organo-mineral complex).
#' 4. The resulting second-quantised Hamiltonian is mapped to qubits
#'    by the chosen fermion-to-qubit transformation; by default the
#'    `ParityMapper` is used with known particle numbers, which
#'    taper off two qubits by Z2 symmetry reduction.
#'
#' The returned object is a standard
#' `edaphos_quantum_hamiltonian` and can be dropped straight into
#' [quantum_vqe_fit()] or [quantum_ibmq_submit()]. It additionally
#' exposes the full set of energy shifts as attributes so the user
#' can recompute the total molecular energy from a VQE result:
#' \deqn{E_\mathrm{total} = \langle H \rangle_\mathrm{VQE} +
#'                         E_\mathrm{shift}}
#' where
#' \eqn{E_\mathrm{shift} = E_\mathrm{nuc} +
#'                         E_\mathrm{frozen} +
#'                         E_\mathrm{active}}
#' sums the nuclear-repulsion constant, the frozen-core shift
#' (zero when `freeze_core = FALSE`) and the active-space
#' projection shift (zero when no active-space transformation is
#' applied). The helper [quantum_nature_total_energy()] performs
#' this reconstruction on a fit object.
#'
#' @param atom Character — the PySCF atom specification, one atom
#'   per semicolon-separated block, e.g.
#'   `"H 0 0 0; H 0 0 0.735"` (H2 at 0.735 Angstroms) or
#'   `"C 0 0 0; O 1.21 0 0; O -0.63 1.08 0; H -0.3 -0.99 0; H -1.56 0.85 0"`
#'   (formic acid).
#' @param basis Character — the atomic-orbital basis set. Default
#'   `"sto3g"`. Use `"631g"`, `"ccpvdz"`, or larger for chemistry-
#'   grade accuracy at the cost of more qubits.
#' @param charge Integer — molecular charge. Default `0`.
#' @param spin Integer — `2S`, i.e. number of unpaired electrons.
#'   Default `0` (closed shell).
#' @param freeze_core Logical — apply the frozen-core approximation
#'   before the active-space transformation. Default `TRUE`.
#' @param num_active_electrons Optional integer — size of the active
#'   electron space (after freezing the core). When `NULL`, no
#'   active-space reduction is applied (all frontier orbitals kept).
#' @param num_active_orbitals Optional integer — size of the active
#'   orbital space.
#' @param mapper Character — fermion-to-qubit mapping. One of
#'   `"parity"` (default, with tapering by particle-number symmetry),
#'   `"jordan_wigner"`, `"bravyi_kitaev"`.
#' @return An `edaphos_quantum_hamiltonian` carrying the Pauli-string
#'   Hamiltonian of the active-space problem. The object additionally
#'   exposes the following attributes:
#'   \describe{
#'     \item{`nuclear_repulsion_energy`}{Nuclear-nuclear Coulomb
#'       repulsion (constant).}
#'     \item{`frozen_core_shift`}{Constant energy shift introduced by
#'       the frozen-core transformation (0 when
#'       `freeze_core = FALSE`).}
#'     \item{`reference_energy`}{Hartree-Fock reference energy of the
#'       active-space problem.}
#'     \item{`num_particles`}{Length-2 integer vector
#'       `c(alpha, beta)` — the number of spin-up and spin-down
#'       electrons in the active space.}
#'     \item{`num_spatial_orbitals`}{Number of active spatial
#'       orbitals.}
#'     \item{`geometry, basis, charge, spin, mapper`}{Echoed inputs.}
#'   }
#' @references
#' Sun, Q. et al. (2018). PySCF: the Python-based simulations of
#' chemistry framework. *WIREs Computational Molecular Science* **8**,
#' e1340.
#'
#' Bravyi, S. et al. (2017). Tapering off qubits to simulate fermionic
#' Hamiltonians. arXiv:1701.08213.
#' @seealso [quantum_hamiltonian_organo_mineral_nature()] for curated
#'   presets; [quantum_vqe_fit()] to minimise the returned
#'   Hamiltonian.
#' @examples
#' \dontrun{
#'   # H2 at equilibrium bond length, 2 qubits after parity tapering:
#'   h2 <- quantum_hamiltonian_from_pyscf(
#'     atom = "H 0 0 0; H 0 0 0.735",
#'     basis = "sto3g", charge = 0, spin = 0
#'   )
#'   fit <- quantum_vqe_fit(h2, seed = 1L)
#'   fit$energy + attr(h2, "nuclear_repulsion_energy")
#' }
#' @export
quantum_hamiltonian_from_pyscf <- function(atom,
                                             basis = "sto3g",
                                             charge = 0L,
                                             spin   = 0L,
                                             freeze_core = TRUE,
                                             num_active_electrons = NULL,
                                             num_active_orbitals  = NULL,
                                             mapper = c("parity",
                                                        "jordan_wigner",
                                                        "bravyi_kitaev")) {
  .qn_require()
  stopifnot(is.character(atom), length(atom) == 1L, nzchar(atom))
  mapper <- match.arg(mapper)

  driver <- .qk_env$qn_drivers$PySCFDriver(
    atom   = atom,
    basis  = basis,
    charge = as.integer(charge),
    spin   = as.integer(spin)
  )
  problem <- driver$run()

  frozen_shift <- 0
  if (isTRUE(freeze_core)) {
    fc <- .qk_env$qn_transf$FreezeCoreTransformer()
    problem <- fc$transform(problem)
  }
  if (!is.null(num_active_electrons) &&
      !is.null(num_active_orbitals)) {
    ast <- .qk_env$qn_transf$ActiveSpaceTransformer(
      num_electrons        = as.integer(num_active_electrons),
      num_spatial_orbitals = as.integer(num_active_orbitals)
    )
    problem <- ast$transform(problem)
  }

  ham_op <- problem$hamiltonian$second_q_op()
  # `num_particles` is a Python tuple (alpha, beta). Pass it through
  # untouched so ParityMapper sees the fermionic particle count.
  np_py    <- problem$num_particles
  qmap     <- .qn_make_mapper(mapper, np_py)
  qubit_op <- qmap$map(ham_op)

  terms <- .qn_sparsepauliop_to_list(qubit_op)
  n_qubits <- as.integer(qubit_op$num_qubits)
  ham <- quantum_hamiltonian(terms, n_qubits = n_qubits)

  # Enrich the result with the book-keeping constants and metadata
  # so the caller can reconstruct the total molecular energy as
  #     E_total = <H>_VQE + sum(energy_shifts).
  # `problem$hamiltonian$constants` is a dict that always contains
  # the `nuclear_repulsion_energy`, and — when the corresponding
  # transformer was applied — one entry per transformer accounting
  # for the constant contribution of the inactive space.
  constants <- tryCatch(
    reticulate::py_to_r(problem$hamiltonian$constants),
    error = function(e) list()
  )
  constants <- lapply(constants, as.numeric)
  nuc_rep <- as.numeric(constants[["nuclear_repulsion_energy"]]
                         %||% problem$nuclear_repulsion_energy
                         %||% NA_real_)
  frozen_shift <- as.numeric(
    constants[["FreezeCoreTransformer"]] %||% 0
  )
  active_shift <- as.numeric(
    constants[["ActiveSpaceTransformer"]] %||% 0
  )
  total_shift <- sum(unlist(constants), na.rm = TRUE)
  ref_e <- tryCatch(
    as.numeric(problem$reference_energy),
    error = function(e) NA_real_
  )
  np_r <- tryCatch(as.integer(reticulate::py_to_r(np_py)),
                    error = function(e) c(NA_integer_, NA_integer_))
  n_spatial <- tryCatch(as.integer(problem$num_spatial_orbitals),
                         error = function(e) NA_integer_)

  attr(ham, "nuclear_repulsion_energy") <- nuc_rep
  attr(ham, "frozen_core_shift")        <- frozen_shift
  attr(ham, "active_space_shift")       <- active_shift
  attr(ham, "energy_shift")             <- total_shift
  attr(ham, "reference_energy")         <- ref_e
  attr(ham, "num_particles")            <- np_r
  attr(ham, "num_spatial_orbitals")     <- n_spatial
  attr(ham, "geometry") <- atom
  attr(ham, "basis")    <- basis
  attr(ham, "charge")   <- as.integer(charge)
  attr(ham, "spin")     <- as.integer(spin)
  attr(ham, "mapper")   <- mapper
  class(ham) <- c("edaphos_quantum_hamiltonian_nature",
                  class(ham))
  ham
}

# --- curated organo-mineral presets ------------------------------------------

# Geometry strings are stored as package-private constants so they
# can be reused by tests + vignette + users without re-typing the
# XYZ coordinates. All geometries are reasonable B3LYP/6-31G(d)
# optimised geometries rounded to 2 decimal places (Angstroms),
# small enough to fit a VQE in minutes on a laptop.

.qn_geometries <- list(

  # Formic acid HCOOH -- a minimal proxy for the carboxylate
  # functional group that dominates humic acid chemistry. 5 atoms,
  # closed-shell, nuclear charge 24. After frozen-core + (2e, 2o)
  # projection and ParityMapper tapering the Hamiltonian is 2-qubit
  # and ~5 Pauli terms; ideal for fast, reproducible VQE examples.
  formic_acid = paste(
    "C  0.00  0.40  0.00",
    "O  1.13 -0.11  0.00",
    "O -1.00 -0.41  0.00",
    "H  0.00  1.50  0.00",
    "H -1.82  0.14  0.00",
    sep = "; "
  ),

  # Methanediol H2C(OH)2 -- simplest ortho-diol: a structural proxy
  # for the catechol-style hydroxyl motif that chelates Fe(III) in
  # humic substances. 7 atoms, closed-shell.
  methanediol = paste(
    "C  0.00  0.00  0.00",
    "O  1.20  0.60  0.00",
    "O -1.20  0.60  0.00",
    "H  0.00 -0.60  0.95",
    "H  0.00 -0.60 -0.95",
    "H  1.90  0.00  0.00",
    "H -1.90  0.00  0.00",
    sep = "; "
  ),

  # Formate anion HCOO- bound to a bare Fe(III) centre via a single
  # monodentate Fe-O contact -- a minimal cartoon of a carboxylate
  # group coordinating a ferric oxide surface site in a clay-humus
  # complex. 4 atoms plus Fe(III); open-shell (S=5/2). Provided for
  # advanced users; requires a larger active space than the default
  # closed-shell organic variants and is NOT executed in tests.
  ferric_formate = paste(
    "Fe 0.00  0.00  0.00",
    "O  1.90  0.00  0.00",
    "C  3.20  0.60  0.00",
    "O  3.60 -0.60  0.00",
    "H  3.85  1.50  0.00",
    sep = "; "
  )
)

#' Organo-mineral Hamiltonians derived from ab initio molecular models
#'
#' Curated presets that build an `edaphos_quantum_hamiltonian` from a
#' realistic molecular geometry through
#' [quantum_hamiltonian_from_pyscf()]. Three variants are shipped,
#' each chosen to expose a distinct piece of organo-mineral chemistry
#' at a qubit count that is accessible to present-day hardware:
#'
#' \describe{
#'   \item{`"formic_acid"` (default)}{HCOOH in STO-3G with the chemical
#'     core frozen and a `(2e, 2o)` active space. Models the
#'     **carboxylate functional group** that is the dominant
#'     coordinating moiety of humic acids. After parity tapering the
#'     qubit Hamiltonian is 2 qubits / ~5 Pauli terms — fast enough
#'     to run on any hardware and small enough for CI.}
#'   \item{`"methanediol"`}{H\eqn{_2}C(OH)\eqn{_2} in STO-3G with the
#'     core frozen and a `(2e, 2o)` active space. Models the
#'     **ortho-diol** motif that underpins catechol-type Fe(III)
#'     chelation in humic substances. 2 qubits after tapering.}
#'   \item{`"ferric_formate"`}{Monodentate Fe(III)–OOCH complex in
#'     STO-3G. Open-shell (S = 5/2), requires a `(4e, 4o)` active
#'     space around Fe 3d + carboxylate \eqn{\pi^*}, and produces a
#'     4-qubit Hamiltonian after parity tapering. This variant is
#'     the *minimum viable* representation of an organo-mineral
#'     coordination event at the clay–humus interface; because the
#'     SCF convergence is sensitive to the initial guess we
#'     recommend running it on `backend = "aer_shots"` or
#'     `"ibmq"` with `"SPSA"` and at least 100 iterations, and
#'     consulting `attr(ham, "reference_energy")` as a sanity
#'     check.}
#' }
#'
#' @param variant Character — `"formic_acid"` (default),
#'   `"methanediol"` or `"ferric_formate"`.
#' @param basis Character — PySCF basis set label. Default
#'   `"sto3g"` for speed; upgrade to `"631g"` for quantitative work.
#' @param num_active_electrons,num_active_orbitals Optional integer
#'   overrides for the active-space size. When left `NULL` the
#'   variant-specific default is used (`(2, 2)` for the closed-shell
#'   organics, `(4, 4)` for ferric formate).
#' @param mapper Character — fermion-to-qubit mapping; see
#'   [quantum_hamiltonian_from_pyscf()].
#' @return An `edaphos_quantum_hamiltonian_nature` (which inherits
#'   from `edaphos_quantum_hamiltonian`) carrying the qubit
#'   Hamiltonian plus the nuclear-repulsion, frozen-core and
#'   reference-energy attributes needed to reconstruct the total
#'   molecular energy.
#' @references
#' Stevenson, F. J. (1994). *Humus Chemistry: Genesis, Composition,
#' Reactions*. Wiley. (Chapter on carboxylate and catechol-type
#' chelation of Fe(III) at mineral surfaces.)
#' @seealso [quantum_hamiltonian_from_pyscf()],
#'   [quantum_hamiltonian_organo_mineral()] (toy 4-qubit variant),
#'   [quantum_vqe_fit()].
#' @examples
#' \dontrun{
#'   ham <- quantum_hamiltonian_organo_mineral_nature("formic_acid")
#'   attr(ham, "nuclear_repulsion_energy")
#'   quantum_vqe_fit(ham, seed = 1L)$energy +
#'     attr(ham, "nuclear_repulsion_energy")
#' }
#' @export
quantum_hamiltonian_organo_mineral_nature <- function(
    variant = c("formic_acid", "methanediol", "ferric_formate"),
    basis                = "sto3g",
    num_active_electrons = NULL,
    num_active_orbitals  = NULL,
    mapper               = c("parity", "jordan_wigner",
                             "bravyi_kitaev")) {
  variant <- match.arg(variant)
  mapper  <- match.arg(mapper)
  atom <- .qn_geometries[[variant]]

  defaults <- switch(
    variant,
    formic_acid    = list(charge = 0L, spin = 0L,
                           n_e = 2L, n_o = 2L),
    methanediol    = list(charge = 0L, spin = 0L,
                           n_e = 2L, n_o = 2L),
    ferric_formate = list(charge = 0L, spin = 5L,
                           n_e = 4L, n_o = 4L)
  )
  n_e <- if (is.null(num_active_electrons)) defaults$n_e else
    as.integer(num_active_electrons)
  n_o <- if (is.null(num_active_orbitals)) defaults$n_o else
    as.integer(num_active_orbitals)

  ham <- quantum_hamiltonian_from_pyscf(
    atom                 = atom,
    basis                = basis,
    charge               = defaults$charge,
    spin                 = defaults$spin,
    freeze_core          = TRUE,
    num_active_electrons = n_e,
    num_active_orbitals  = n_o,
    mapper               = mapper
  )
  attr(ham, "variant") <- variant
  ham
}

#' Total molecular energy from an active-space VQE result
#'
#' Adds the three constant shifts carried by a
#' `edaphos_quantum_hamiltonian_nature` (nuclear repulsion + frozen
#' core + active-space projection) onto the VQE-estimated electronic
#' energy of the active space.
#'
#' @param fit A `edaphos_quantum_vqe` fit whose `hamiltonian` is a
#'   `edaphos_quantum_hamiltonian_nature`.
#' @return A numeric scalar — the total molecular energy in Hartree.
#' @export
quantum_nature_total_energy <- function(fit) {
  stopifnot(inherits(fit, "edaphos_quantum_vqe"),
            inherits(fit$hamiltonian,
                     "edaphos_quantum_hamiltonian_nature"))
  shift <- attr(fit$hamiltonian, "energy_shift")
  if (is.null(shift) || !is.finite(shift)) {
    shift <- sum(
      c(attr(fit$hamiltonian, "nuclear_repulsion_energy") %||% 0,
        attr(fit$hamiltonian, "frozen_core_shift")        %||% 0,
        attr(fit$hamiltonian, "active_space_shift")       %||% 0),
      na.rm = TRUE
    )
  }
  as.numeric(fit$energy + shift)
}

#' @export
print.edaphos_quantum_hamiltonian_nature <- function(x, ...) {
  cat("<edaphos_quantum_hamiltonian_nature>\n")
  variant <- attr(x, "variant") %||% "(user geometry)"
  cat(sprintf("  variant     : %s\n", variant))
  cat(sprintf("  basis       : %s     mapper : %s\n",
              attr(x, "basis") %||% "?",
              attr(x, "mapper") %||% "?"))
  np <- attr(x, "num_particles")
  np_desc <- if (is.null(np) || anyNA(np)) "?" else
    sprintf("(a=%d, b=%d)", np[1L], np[2L])
  cat(sprintf("  active sp.  : %s particles / %s spatial orbitals\n",
              np_desc,
              format(attr(x, "num_spatial_orbitals") %||% NA)))
  cat(sprintf("  qubits      : %d   n_terms : %d\n",
              x$n_qubits, length(x$pauli_terms)))
  cat(sprintf("  nuc_rep     : %.6f   frozen : %.6f\n",
              attr(x, "nuclear_repulsion_energy") %||% NA_real_,
              attr(x, "frozen_core_shift")        %||% NA_real_))
  cat(sprintf("  active_shft : %.6f   ref_E  : %.6f\n",
              attr(x, "active_space_shift") %||% NA_real_,
              attr(x, "reference_energy")   %||% NA_real_))
  invisible(x)
}
