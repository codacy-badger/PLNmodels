#' An R6 Class to represent a collection of PLNnetworkfit
#'
#' @description The function \code{\link{PLNnetwork}} produces an instance of this class.
#'
#' This class comes with a set of methods, some of them being useful for the user:
#' See the documentation for \code{\link[=getBestModel.PLNnetworkfamily]{getBestModel}},
#' \code{\link[=getModel.PLNnetworkfamily]{getModel}} and  \code{\link[=plot.PLNnetworkfamily]{plot}}.
#'
#' @field responses the matrix of responses common to every models
#' @field covariates the matrix of covariates common to every models
#' @field offsets the matrix of offsets common to every models
#' @field penalties the sparsity level of the network in the successively fitted models
#' @field models a list of \code{\link[=PLNnetworkfit]{PLNnetworkfit}} object, one per penalty.
#' @field inception a \code{\link[=PLNfit]{PLNfit}} object, obtained when no sparsifying penalty is applied.
#' @field criteria a data frame with the value of some criteria (variational lower bound J, BIC, ICL and R2) for the different models.
#' @include PLNfamily-class.R
#' @importFrom R6 R6Class
#' @importFrom glassoFast glassoFast
#' @seealso The function \code{\link{PLNnetwork}}, the class \code{\link[=PLNnetworkfit]{PLNnetworkfit}}
PLNnetworkfamily <-
  R6Class(classname = "PLNnetworkfamily",
    inherit = PLNfamily,
    private = list(
      stab_path = NULL
      ), # a field to store the stability path,
    active = list(
      penalties = function() private$params,
      stability_path = function() private$stab_path,
      stability = function() {
        if (!is.null(private$stab_path)) {
          stability <- self$stability_path %>%
            dplyr::select(Penalty, Prob) %>%
            group_by(Penalty) %>%
            summarize(Stability = 1 - mean(4 * Prob * (1 - Prob))) %>%
            arrange(desc(Penalty)) %>%
            pull(Stability)
        } else {
          stability <- rep(NA, length(self$penalties))
        }
        stability
      },
      criteria = function() {mutate(super$criteria, stability = self$stability)}
    )
)

PLNnetworkfamily$set("public", "initialize",
  function(penalties, responses, covariates, offsets, weights, model, control) {

    ## initialize fields shared by the super class
    super$initialize(responses, covariates, offsets, weights, control)
    ## Get an appropriate grid of penalties
    if (is.null(penalties)) {
      if (control$trace > 1) cat("\n Recovering an appropriate grid of penalties.")
      myPLN <- PLNfit$new(responses, covariates, offsets, weights, model, control)
      myPLN$optimize(responses, covariates, offsets, weights, control)
      max_pen <- max(abs(myPLN$model_par$Sigma))
      control$inception <- myPLN
      penalties <- 10^seq(log10(max_pen), log10(max_pen*control$min.ratio), len = control$nPenalties)
    } else {
      if (control$trace > 1) cat("\nPenalties already set by the user")
      stopifnot(all(penalties > 0))
    }

    ## instantiate as many models as penalties
    private$params <- sort(penalties, decreasing = TRUE)
    self$models <- lapply(private$params, function(penalty) {
      PLNnetworkfit$new(penalty, responses, covariates, offsets, weights, model, control)
    })

})

PLNnetworkfamily$set("public", "optimize",
  function(control) {

  ## Go along the penalty grid (i.e the models)
  for (m in seq_along(self$models))  {

    if (control$trace == 1) {
      cat("\tsparsifying penalty =", self$models[[m]]$penalty, "\r")
      flush.console()
    }
    if (control$trace > 1) {
      cat("\tsparsifying penalty =", self$models[[m]]$penalty, "- iteration:")
    }
    self$models[[m]]$optimize(self$responses, self$covariates, self$offsets, self$weights, control)
    ## Save time by starting the optimization of model m+1  with optimal parameters of model m
    if (m < length(self$penalties))
      self$models[[m + 1]]$update(
          Theta = self$models[[m]]$model_par$Theta,
          Sigma = self$models[[m]]$model_par$Sigma,
          M     = self$models[[m]]$var_par$M,
          S     = self$models[[m]]$var_par$S
        )

    if (control$trace > 1) {
      cat("\r                                                                                    \r")
      flush.console()
    }

  }

})

#' Compute the stability path by stability selection
#'
#' @name stability_selection
#' @param subsamples a list of vectors describing the subsamples. The number of vectors (or list length) determines th number of subsamples used in the stability selection. Automatically set to 20 subsamples with size \code{10*sqrt(n)} if \code{n >= 144} and \code{0.8*n} otherwise following Liu et al. (2010) recommandations.
#' @param control a list controling the main optimization process in each call to PLNnetwork. See \code{\link[=PLNnetwork]{PLNnetwork}} for details.
#' @param mc.cores the number of cores to used. Default is 1.
#'
##' @return the list of subsamples. The estimated probabilities of selection of the edges are stored in the fields stability_path of the PLNnetwork object
NULL
PLNnetworkfamily$set("public", "stability_selection",
  function(subsamples = NULL, control = list(), mc.cores = 1) {

    ## select default subsamples according
    if (is.null(subsamples)) {
      subsample.size <- round(ifelse(private$n >= 144, 10*sqrt(private$n), 0.8*private$n))
      subsamples <- replicate(20, sample.int(private$n, subsample.size), simplify = FALSE)
    }

    ## got for stability selection
    cat("\nStability Selection for PLNnetwork: ")
    cat("\nsubsampling: ")

    stabs_out <- mclapply(subsamples, function(subsample) {
      cat("+")
      inception_ <- self$getModel(self$penalties[1])
      inception_$update(
        M = inception_$var_par$M[subsample, ],
        S = inception_$var_par$S[subsample, ]
      )

      ctrl_init <- PLN_param(list(), inception_$n, inception_$p, inception_$d)
      ctrl_init$trace <- 0
      ctrl_init$inception <- inception_
      myPLN <- PLNnetworkfamily$new(penalties  = self$penalties,
                                    responses  = self$responses [subsample, , drop = FALSE],
                                    covariates = self$covariates[subsample, , drop = FALSE],
                                    offsets    = self$offsets   [subsample, , drop = FALSE],
                                    model      = private$model,
                                    weights    = self$weights   [subsample], control = ctrl_init)

      ctrl_main <- PLNnetwork_param(control, inception_$n, inception_$p, inception_$d, !all(self$weights == 1))
      ctrl_main$trace <- 0
      myPLN$optimize(ctrl_main)
      nets <- do.call(cbind, lapply(myPLN$models, function(model) {
        as.matrix(model$latent_network("support"))[upper.tri(diag(private$p))]
      }))
      nets
    }, mc.cores = mc.cores)

    prob <- Reduce("+", stabs_out, accumulate = FALSE) / length(subsamples)
    ## formatting/tyding
    colnames(prob) <- self$penalties
    private$stab_path <- prob %>%
      as.data.frame() %>%
      mutate(Edge = 1:n()) %>%
      gather(key = "Penalty", value = "Prob", -Edge) %>%
      mutate(Penalty = as.numeric(Penalty),
             Node1   = as.character(edge_to_node(Edge)$node1),
             Node2   = as.character(edge_to_node(Edge)$node2),
             Edge    = paste0(Node1, "--", Node2)) %>%
      filter(Node1 < Node2)

    invisible(subsamples)
  }
)


#' Extract the regularization path of a PLNnetwork fit
#'
#' @name coefficient_path
#' @param precision a logical, should the coefficients of the precision matrix Omega or the covariance matrice Sigma be sent back. Default is \code{TRUE}.
#' @param corr a logical, should the correlation (partial in case  precision = TRUE) be sent back. Default is \code{TRUE}.
#'
#' @return  Send back a tibble/data.frame.
NULL
PLNnetworkfamily$set("public", "coefficient_path",
function(precision = TRUE, corr = TRUE) {
  lapply(self$penalties, function(x) {
    if (precision) {
      G <- self$getModel(x)$model_par$Omega
    } else {
      G <- self$getModel(x)$model_par$Sigma
      dimnames(G) <- dimnames(self$getModel(x)$model_par$Omega)
    }
    if (corr) {
      G <- ifelse(precision, -1, 1) * G / tcrossprod(sqrt(diag(G)))
    }
    G %>% melt(value.name = "Coeff", varnames = c("Node1", "Node2")) %>%
      mutate(Penalty = x,
             Node1   = as.character(Node1),
             Node2   = as.character(Node2),
             Edge    = paste0(Node1, "--", Node2)) %>%
      filter(Node1 < Node2)
  }) %>% bind_rows()
})

#' Best model extraction from a collection of PLNnetworkfit
#'
#' @name getBestModel.PLNnetworkfamily
#'
#' @param Robject an object with class PLNnetworkfamilly
#' @param crit a character for the criterion used to performed the selection. Either
#' "BIC", "EBIC", "StARS", "R_squared". Default is \code{BIC}. If StARS
#' (Stability Approach to Regularization Selection) is chosen and stability selection
#'  was not yet performed, the function will call the method stability_selection with default argument.
#' @param ... additional parameters for StARS criterion. stability, a scalar indicating the target stability (= 1 - 2 beta) at which the network is selected. Default is \code{0.9}.
#' @return  Send back a object with class \code{\link[=PLNnetworkfit]{PLNnetworkfit}}.
#' @export
getBestModel.PLNnetworkfamily <- function(Robject, crit = c("BIC", "loglik", "R_squared", "EBIC", "StARS"), ...) {
  stopifnot(isPLNnetworkfamily(Robject))
  stability <- list(...)[["stability"]]
  if (is.null(stability)) stability <- 0.9
  Robject$getBestModel(match.arg(crit), stability)
}

PLNnetworkfamily$set("public", "getBestModel",
function(crit = c("BIC", "loglik", "R_squared", "EBIC", "StARS"), stability = 0.9){
  crit <- match.arg(crit)
  if (crit == "StARS") {
    if (is.null(private$stab_path)) self$stability_selection()
    id_stars <- self$criteria %>%
      select(param, stability) %>% rename(Stability = stability) %>%
      filter(Stability > stability) %>%
      pull(param) %>% min() %>% match(self$penalties)
    model <- self$models[[id_stars]]$clone()
  } else {
    stopifnot(!anyNA(self$criteria[[crit]]))
    id <- 1
    if (length(self$criteria[[crit]]) > 1) {
      id <- which.max(self$criteria[[crit]])
    }
    model <- self$models[[id]]$clone()
  }
  model
})

#' Model extraction from a collection of PLNnetwork models
#'
#' @name getModel.PLNnetworkfamily
#'
#' @param Robject an R6 object with class PLNfamily
#' @param var value of the parameter (penalty for sparse network) that identifies the model to be extracted from the collection. If no exact match is found, the model with closest parameter value is returned with a warning.
#' @param index Integer index of the model to be returned. Only the first value is taken into account.
#'
#' @return Sends back a object with class \code{\link[=PLNnetworkfit]{PLNnetworkfit}}.
#'
#' @export
getModel.PLNnetworkfamily <- function(Robject, var, index = NULL) {
  stopifnot(isPLNnetworkfamily(Robject))
  Robject$getModel(var, index = NULL)
}


## ----------------------------------------------------------------------
## PUBLIC PLOTTING METHODS
## ----------------------------------------------------------------------

#' Display the criteria associated with a collection of PLNnetwork fits (a PLNnetworkfamily)
#'
#' @name plot.PLNnetworkfamily
#'
#' @param x an R6 object with class PLNfamily
#' @param criteria vector of characters. The criteria to plot in c("loglik", "BIC", "ICL", "R_squared", "EBIC", "pen_loglik").
#' Default is  c("loglik", "pen_loglik", "BIC", "EBIC").
#' @param log.x logical: should the x-axis be repsented in log-scale? Default is \code{TRUE}.
#' @param annotate logical: should the value of approximated R squared be added to the plot? Default is \code{TRUE}.
#' @param ... additional parameters for S3 compatibility. Not used
#'
#' @return Produces a plot  representing the evolution of the criteria of the different models considered,
#' highlighting the best model in terms of BIC and EBIC.
#'
#' @export
plot.PLNnetworkfamily <- function(x, criteria = c("loglik", "pen_loglik", "BIC", "EBIC"), log.x = TRUE, annotate = TRUE,...) {
  stopifnot(isPLNnetworkfamily(x))
  x$plot(criteria, annotate)
}

PLNnetworkfamily$set("public", "plot",
function(criteria = c("loglik", "pen_loglik", "BIC", "EBIC"), log.x = TRUE, annotate) {
  vlines <- sapply(intersect(criteria, c("BIC", "EBIC")) , function(crit) self$getBestModel(crit)$penalty)
  p <- super$plot(criteria, FALSE) + xlab("penalty") + geom_vline(xintercept = vlines, linetype = "dashed", alpha = 0.25)
  if (log.x) p <- p + ggplot2::coord_trans(x = "log10")
  p
})

#' @export
PLNnetworkfamily$set("public", "plot_stars",
function(stability = 0.9, log.x = TRUE) {
  dplot <- self$criteria %>% select(param, density, stability) %>%
    rename(Penalty = param) %>%
    gather(key = "Metric", value = "Value", stability:density)
  penalty_stars <- dplot %>% filter(Metric == "stability" & Value >= stability) %>%
    pull(Penalty) %>% min()

  p <- ggplot(dplot, aes(x = Penalty, y = Value, group = Metric, color = Metric)) +
    geom_point() +  geom_line() + theme_bw() +
    ## Add information correspinding to best lambda
    geom_vline(xintercept = penalty_stars, linetype = 2) +
    geom_hline(yintercept = stability, linetype = 2) +
    annotate(x = penalty_stars, y = 0,
           label = paste("lambda == ", round(penalty_stars, 5)),
           parse = TRUE, hjust = -0.05, vjust = 0, geom = "text") +
    annotate(x = penalty_stars, y = stability,
             label = paste("stability == ", stability),
             parse = TRUE, hjust = -0.05, vjust = 1.5, geom = "text")
  if (log.x) p <- p + ggplot2::scale_x_log10() + annotation_logticks(sides = "b")
  p
})


#' @export
PLNnetworkfamily$set("public", "plot_objective",
function() {
  objective <- unlist(lapply(self$models, function(model) model$optim_par$objective))
  changes <- cumsum(unlist(lapply(self$models, function(model) model$optim_par$outer_iterations)))
  dplot <- data.frame(iteration = 1:length(objective), objective = objective)
  p <- ggplot(dplot, aes(x = iteration, y = objective)) + geom_line() +
    geom_vline(xintercept = changes, linetype="dashed", alpha = 0.25) +
    ggtitle("Objective along the alternate algorithm") + xlab("iteration (+ changes of model)") +
    annotate("text", x = changes, y = min(dplot$objective), angle = 90,
             label = paste("penalty=",format(self$criteria$param, digits = 1)), hjust = -.1, size = 3, alpha = 0.7) + theme_bw()
  p
})

PLNnetworkfamily$set("public", "show",
function() {
  super$show()
  cat(" Task: Network Inference \n")
  cat("========================================================\n")
  cat(" -", length(self$penalties) , "penalties considered: from", min(self$penalties), "to", max(self$penalties),
      "\n", "   use $penalties to see all values and access specific lambdas", "\n")
  if (!anyNA(self$criteria$stability))
    cat(" - Best model (regarding StARS): lambda =", format(self$getBestModel("StARS")$penalty, digits = 3), "\n")
  if (!anyNA(self$criteria$BIC))
    cat(" - Best model (regarding BIC): lambda =", format(self$getBestModel("BIC")$penalty, digits = 3), "\n")
})
PLNnetworkfamily$set("public", "print", function() self$show())

