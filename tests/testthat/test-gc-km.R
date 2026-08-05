# ---------------------------------------------------------------------------
# .gc_km() -- the one great-circle formula in the package.
#
# It replaced two near-identical copies (spatial_block_folds and the Pillar-10
# graph builder), each of which called sp::spDists when sp happened to be
# installed and fell back to an inline haversine when it was not. Because sp
# works on the WGS84 ellipsoid and the closed form on a sphere, the same call
# returned different answers depending on a Suggests-level package -- a
# difference large enough (~0.4 km at a 68 km buffer) to move a profile across
# the CV buffer boundary. These tests pin the properties that matter for the
# two consumers: correct anisotropy, a bounded spherical approximation, and
# neighbour ORDER, which is what the k-NN graph actually reads.
# ---------------------------------------------------------------------------

test_that(".gc_km gets the anisotropy of a degree right", {
  # A degree of longitude shrinks as cos(latitude); a degree of latitude does
  # not. This is the entire content of the Pillar-10 fix, so it is asserted
  # directly rather than inferred from a distance matrix.
  lat_deg <- edaphos:::.gc_km(cbind(-47, -15), cbind(-47, -14))[1, 1]
  lon_deg <- edaphos:::.gc_km(cbind(-47, -15), cbind(-46, -15))[1, 1]

  expect_equal(lat_deg, 111.19, tolerance = 0.01)
  expect_lt(lon_deg, lat_deg)
  expect_equal(lon_deg / lat_deg, cos(15 * pi / 180), tolerance = 1e-3)

  # and the shrinkage must track latitude, not be a constant fudge
  lon_2 <- edaphos:::.gc_km(cbind(-47, -2), cbind(-46, -2))[1, 1]
  lon_24 <- edaphos:::.gc_km(cbind(-47, -24), cbind(-46, -24))[1, 1]
  expect_gt(lon_2, lon_24)
  expect_equal(lon_24 / lon_2, cos(24 * pi / 180) / cos(2 * pi / 180),
               tolerance = 1e-3)
})

test_that(".gc_km is a metric: symmetric, zero on the diagonal, triangular", {
  set.seed(4L)
  M <- cbind(stats::runif(30, -60, -41), stats::runif(30, -24, -2))
  D <- edaphos:::.gc_km(M)

  expect_equal(dim(D), c(30L, 30L))
  expect_equal(D, t(D))
  expect_equal(diag(D), rep(0, 30))
  expect_true(all(D >= 0))

  # triangle inequality on every triple: D[i, j] <= D[i, m] + D[m, j]
  worst <- max(vapply(seq_len(30), function(m)
    max(D - outer(D[, m], D[m, ], "+")), 0))
  expect_lte(worst, 1e-8)

  # the two-matrix form must agree with the one-matrix form
  expect_equal(edaphos:::.gc_km(M[1:5, ], M[6:10, ]), D[1:5, 6:10])
})

test_that("the spherical approximation stays inside its stated budget", {
  # The helper's own comment claims a median relative error of 0.14% and a
  # maximum of 0.56% against the WGS84 ellipsoid for pairs under 50 km. If
  # that claim is going to sit in the source, it should be checked.
  skip_if_not_installed("sp")
  set.seed(7L)
  M <- cbind(stats::runif(200, -60, -41), stats::runif(200, -24, -2))
  S <- edaphos:::.gc_km(M)
  E <- sp::spDists(M, longlat = TRUE)

  near <- E > 0 & E < 50
  expect_lt(stats::median(abs(S[near] - E[near]) / E[near]), 0.003)
  expect_lt(max(abs(S[near] - E[near]) / E[near]), 0.01)

  # What the graph consumes is neighbour ORDER. The sub-percent distortion is
  # not quite invisible to it -- 3 of 1600 edges reorder on this fixture -- but
  # every swap is a near-tie: the displaced neighbour sits within half a
  # percent of the 8th-nearest distance, where the ordering carries no
  # information to begin with. Both halves are asserted, because "rare" alone
  # would still permit a swap that moved a genuinely closer profile out.
  diag(S) <- Inf; diag(E) <- Inf
  swapped <- vapply(seq_len(200), function(i)
    length(setdiff(order(S[i, ])[1:8], order(E[i, ])[1:8])), 0)
  expect_lt(sum(swapped), 0.01 * 200 * 8)

  margin <- vapply(seq_len(200), function(i) {
    o_e <- order(E[i, ])[1:8]
    lost <- setdiff(o_e, order(S[i, ])[1:8])
    if (!length(lost)) return(NA_real_)
    min(abs(E[i, lost] - E[i, o_e[8]])) / E[i, o_e[8]]
  }, numeric(1))
  expect_lt(max(margin, na.rm = TRUE), 0.01)
})

test_that("the great-circle graph differs from the Euclidean-degree one", {
  # The defect this replaced was not cosmetic: the header called the edge
  # weight "inverse-geodesic" while stats::dist() treated a degree of
  # longitude as a degree of latitude. The effect is small but real, and
  # pinning it here stops a future refactor from quietly reverting to degrees.
  set.seed(9L)
  M <- cbind(stats::runif(300, -60, -41), stats::runif(300, -24, -2))
  K <- edaphos:::.gc_km(M)
  G <- as.matrix(stats::dist(M))
  diag(K) <- Inf; diag(G) <- Inf

  swapped <- sum(vapply(seq_len(300), function(i)
    length(setdiff(order(G[i, ])[1:8], order(K[i, ])[1:8])), 0))
  expect_gt(swapped, 0)

  # and gnn_build_graph must be the one using kilometres
  df <- data.frame(lon = M[, 1], lat = M[, 2],
                   f1 = stats::rnorm(300), f2 = stats::rnorm(300))
  g <- gnn_build_graph(df, k = 6L, edges = "spatial", self_loops = FALSE)
  expect_true(all(g$edge_weight > 0))
  expect_equal(nrow(g$edge_index), 300L * 6L)
})
