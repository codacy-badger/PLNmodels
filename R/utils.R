.xlogx <- function(x) ifelse(x < .Machine$double.eps, 0, x*log(x))

.softmax <- function(x) {
  b <- max(x)
  exp(x - b) / sum(exp(x - b))
}

.logfactorial <- function(n) { # Ramanujan's formula
  n[n == 0] <- 1 ## 0! = 1!
  return(n*log(n) - n + log(8*n^3 + 4*n^2 + n + 1/30)/6 + log(pi)/2)
}

logLikPoisson <- function(responses, lambda, weights = rep(1, nrow(responses))) {
  loglik <- rowSums(responses * lambda, na.rm = TRUE) - rowSums(exp(lambda)) - rowSums(.logfactorial(responses))
  loglik <- sum(loglik * weights)
  loglik
}

##' @importFrom stats glm.fit
nullModelPoisson <- function(responses, covariates, offsets, weights = rep(1, nrow(responses))) {
  Theta <- do.call(rbind, lapply(1:ncol(responses), function(j)
    coefficients(glm.fit(covariates, responses[, j], weights = weights, offset = offsets[, j], family = stats::poisson()))))
  lambda <- offsets + tcrossprod(covariates, Theta)
  lambda
}

fullModelPoisson <- function(responses, weights = rep(1, nrow(responses))) {
  lambda <- log(sweep(responses, 1, weights, "*"))
  lambda
}

extract_model <- function(call, envir) {

  ## create the call for the model frame
  call_frame <- call[c(1L, match(c("formula", "data", "subset", "weights"), names(call), 0L))]
  call_frame[[1]] <- quote(stats::model.frame)

  ## eval the call in the parent environment
  frame <- eval(call_frame, envir)

  ## create the set of matrices to fit the PLN model
  Y <- model.response(frame)
  X <- model.matrix(terms(frame), frame)
  O <- model.offset(frame)
  if (is.null(O)) O <- matrix(0, nrow(Y), ncol(Y))
  w <- model.weights(frame)
  if (is.null(w)) {
    w <- rep(1.0, nrow(Y))
  } else {
    stopifnot(all(w > 0) && length(w) == nrow(Y))
  }
  list(Y = Y, X = X, O = O, w = w, model = call$formula)
}

edge_to_node <- function(x, n = max(x)) {
  x <- x - 1 ## easier for arithmetic to number edges starting from 0
  n.node <- round((1 + sqrt(1 + 8*n)) / 2) ## n.node * (n.node -1) / 2 = n (if integer)
  j.grid <- cumsum(0:n.node)
  j <- findInterval(x, vec = j.grid)
  i <- x - j.grid[j]
  ## Renumber i and j starting from 1 to stick with R convention
  return(data.frame(node1 = i + 1, node2 = j + 1))
}

node_pair_to_egde <- function(x, y, node.set = union(x, y)) {
  ## Convert node labels to integers (starting from 0)
  x <- match(x, node.set) - 1
  y <- match(y, node.set) - 1
  ## For each pair (x,y) return, corresponding edge number
  n <- length(node.set)
  j.grid <- cumsum(0:(n - 1))
  x + j.grid[y] + 1
}

##' @title PLN RNG
##'
##' @description Random generation for the PLN model with latent mean equal to mu, latent covariance matrix
##'              equal to Sigma and average depths (sum of counts in a sample) equal to depths
##'
##' @param n the sample size
##' @param mu vectors of means of the latent variable
##' @param Sigma covariance matrix of the latent variable
##' @param depths Numeric vector of target depths. The first is recycled if there are not `n` values
##'
##' @return a n * p count matrix, with row-sums close to depths
##'
##' @details The default value for mu and Sigma assume equal abundances and no correlation between
##'          the different species.
##'
##' @rdname rPLN
##' @examples
##' ## 10 samples of 5 species with equal abundances, no covariance and target depths of 10,000
##' rPLN()
##' ## 2 samples of 10 highly correlated species with target depths 1,000 and 100,000
##' ## very different abundances
##' mu <- rep(c(1, -1), each = 5)
##' Sigma <- matrix(0.8, 10, 10); diag(Sigma) <- 1
##' rPLN(n=2, mu = mu, Sigma = Sigma, depths = c(1e3, 1e5))
##'
##' @importFrom MASS mvrnorm
##' @importFrom stats rpois
##' @export
rPLN <- function(n = 10, mu = rep(0, ncol(Sigma)), Sigma = diag(1, 5, 5), depths = rep(1e4, n)) {
  p <- ncol(Sigma)
  if (any(is.vector(mu), ncol(mu) == 1)) {
    mu <- matrix(rep(mu, n), ncol = p, byrow = TRUE)
  }
  if (length(depths) != n) {
    depths <- rep(depths[1], n)
  }
  ## adjust depths
  exp_depths <- rowSums(exp(diag(Sigma)/2 + mu)) ## sample-wise expected depths
  offsets <- log(depths %o% rep(1, p)) - log(exp_depths)
  Z <- mu + mvrnorm(n, rep(0,ncol(Sigma)), as.matrix(Sigma)) + offsets
  Y <- matrix(rpois(n * p, as.vector(exp(Z))), n, p)
  Y
}

## -----------------------------------------------------------------
##  Series of setter to default parameters for user's main functions
##
## should be ready to pass to nlopt optimizer
PLN_param <- function(control, n, p, d, weighted = FALSE) {
  lower_bound <- ifelse(is.null(control$lower_bound), 1e-4  , control$lower_bound)
  xtol_abs    <- ifelse(is.null(control$xtol_abs)   , 1e-4  , control$xtol_abs)
  covariance  <- ifelse(is.null(control$covariance) , "full", control$covariance)
  covariance  <- ifelse(is.null(control$inception), covariance, control$inception$vcov_model)
  ctrl <- list(
    "algorithm"   = "CCSAQ",
    "maxeval"     = 10000  ,
    "maxtime"     = -1     ,
    "ftol_rel"    = ifelse(n < 1.5*p, 1e-6, 1e-8),
    "ftol_abs"    = 0,
    "xtol_rel"    = 1e-4,
    "xtol_abs"    = c(rep(0   , p*d), rep(0   , p*n), rep(xtol_abs   , ifelse(covariance == "spherical", n, n*p))),
    "lower_bound" = c(rep(-Inf, p*d), rep(-Inf, p*n), rep(lower_bound, ifelse(covariance == "spherical", n, n*p))),
    "trace"       = 1,
    "weighted"    = weighted  ,
    "covariance"  = covariance,
    "inception"   = NULL
  )
  ctrl[names(control)] <- control
  ctrl
}

PLN_param_VE <- function(control, n, p, weighted = FALSE) {
  lower_bound <- ifelse(is.null(control$lower_bound), 1e-4  , control$lower_bound)
  xtol_abs    <- ifelse(is.null(control$xtol_abs)   , 1e-4  , control$xtol_abs)
  covariance  <- ifelse(is.null(control$covariance) , "full", control$covariance)
  ctrl <- list(
    "algorithm"   = "CCSAQ",
    "maxeval"     = 10000  ,
    "maxtime"     = -1     ,
    "ftol_rel"    = ifelse(n < 1.5*p, 1e-6, 1e-8),
    "ftol_abs"    = 0,
    "xtol_rel"    = 1e-4,
    "xtol_abs"    = c(rep(0   , p*n), rep(xtol_abs   , ifelse(covariance == "spherical", n, n*p))),
    "lower_bound" = c(rep(-Inf, p*n), rep(lower_bound, ifelse(covariance == "spherical", n, n*p))),
    "trace"       = 1,
    "weighted"    = weighted  ,
    "covariance"  = covariance,
    "inception"   = NULL
  )
  ctrl[names(control)] <- control
  ctrl
}


PLNPCA_param <- function(control, weighted = FALSE) {
  ctrl <- list(
      "algorithm"   = "CCSAQ" ,
      "ftol_rel"    = 1e-8    ,
      "ftol_abs"    = 0       ,
      "xtol_rel"    = 1e-4    ,
      "xtol_abs"    = 1e-4    ,
      "lower_bound" = 1e-4    ,
      "maxeval"     = 10000   ,
      "maxtime"     = -1      ,
      "trace"       = 1       ,
      "cores"       = 1       ,
      "weighted"    = weighted  ,
      "covariance"  = "rank"
    )
  ctrl[names(control)] <- control
  ctrl
}

PLNnetwork_param <- function(control, n, p, d, weighted = FALSE) {
  lower_bound <- ifelse(is.null(control$lower_bound), 1e-4, control$lower_bound)
  xtol_abs    <- ifelse(is.null(control$xtol_abs)   , 1e-4, control$xtol_abs)
  ctrl <-  list(
    "ftol_out"  = 1e-5,
    "maxit_out" = 50,
    "penalize_diagonal" = TRUE,
    "warm"        = FALSE,
    "algorithm"   = "CCSAQ",
    "ftol_rel"    = 1e-8    ,
    "ftol_abs"    = 0       ,
    "xtol_rel"    = 1e-4    ,
    "xtol_abs"    = c(rep(0, p*d), rep(0, n*p), rep(xtol_abs, n*p)),
    "lower_bound" = c(rep(-Inf, p*d), rep(-Inf, n*p), rep(lower_bound, n*p)),
    "maxeval"     = 10000   ,
    "maxtime"     = -1      ,
    "trace"       = 1       ,
    "weighted"    = weighted,
    "covariance"  = "sparse"
  )
  ctrl[names(control)] <- control
  ctrl
}

statusToMessage <- function(status) {
    message <- switch( status,
        "1"  = "success",
        "2"  = "stopval was reached",
        "3"  = "ftol_rel or ftol_abs was reached",
        "4"  = "xtol_rel or xtol_abs was reached",
        "5"  = "maxeval was reached",
        "6"  = "maxtime was reached",
        "-1" = "failure",
        "-2" = "invalid arguments",
        "-3" = "out of memory.",
        "-4" = "roundoff errors led to a breakdown of the optimization algorithm",
        "-5" = "forced termination:",
        "Return status not recognized"
    )
    message
}
