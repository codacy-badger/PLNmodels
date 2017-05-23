#' An R6 Class to represent a PLNfit in a PCA framework
#'
#' @description The function \code{\link{PLNPCA}} produces a collection of models which are instances of object with class \code{PLNPCAfit}.
#'
#' This class comes with a set of methods, some of them being useful for the user:
#' See the documentation for \code{\link[=PLNPCAfit_plot]{plot}}, \code{\link[=PLNPCAfit_plot_individual.map]{plot_individual.map}}
#' and \code{\link[=PLNPCAfit_plot_correlation.circle]{plot_correlation.circle}}
#'
#' Fields should not be changed or manipulated by the user as they are updated internally.
#'
#' @field type a character indicating the model used for the covariance matrix in the variational Gaussian approximation. Either "diagonal" or "spherical".
#' @field rank the dimension of the current model
#' @field model.par a list with two matrices, B and Theta, which are the estimated parameters of the pPCA model
#' @field variation.par a list with two matrices, M and S, which are the estimated parameters in the variational approximation
#' @field criteria a named vector with the value of some criteria (variational lower bound J, BIC, ICL, R2, lmin and lmax) for the different models.
#' @field convergence numeric; the convergence status of the L-BFGS-B method
#' @field loglik numeric; the Poisson loglikelihood of the current model
#' @field percentVar the percent of variance explained by each axis
#' @field corrCircle a matrix of correlations to plot the correlation circles
#' @field scores a matrix of scores to plot the individual factor maps
#' @include PLNfit-class.R
#' @importFrom R6 R6Class
#' @seealso The function \code{\link{PLNPCA}}, the class \code{\link[=PLNfamily-class]{PLNfamily}}
PLNPCAfit <-
  R6Class(classname = "PLNPCAfit",
    inherit = PLNfit,
    public  = list(
      rank       = NULL,
      percentVar = NULL,
      corrCircle = NULL,
      scores     = NULL,
      initialize = function(rank = NA, percentVar = NA, corrCircle = NA, scores = NA,
                            type=NA, model.par=NA, variational.par=NA, criteria=NA, convergence=NA, loglik=NA) {
        super$initialize(type, model.par, variational.par, criteria, convergence, loglik)
        self$rank       <- rank
        self$percentVar <- percentVar
        self$corrCircle <- corrCircle
        self$scores     <- scores
      }
    )
)

PLNPCAfit$set("public", "setVisualization",
  function(scale.unit=FALSE) {
    svdBM <- svd(scale(t(tcrossprod(self$model.par$B, self$variational.par$M)),TRUE, scale.unit), nv = self$rank)
    d <- svdBM$d[1:self$rank]
    eigen.val <- d^2
    correlations <- t(t(svdBM$v[, 1:self$rank]) * eigen.val)
    self$scores <- t(t(svdBM$u[, 1:self$rank]) * d)
    self$percentVar <- round(eigen.val/sum(eigen.val),4)
    self$corrCircle <- correlations/sqrt(rowSums(correlations^2))
    rownames(self$corrCircle) <- rownames(self$model.par$B)
    rownames(self$scores) <- rownames(self$variational.par$M)
})


#' Plot the individual map of a specified axis for a \code{PLNPCAfit} object
#'
#' @name PLNPCAfit_plot_individual.map
#' @param axes numeric, the axes to use for the plot. Default it c(1,2)
#' @param main character, the title. Default is "Individual Factor Map"
#' @param plot logical. Should the plot be displayed or sent back as a ggplot object
#' @param cols a character, factor or numeric to defined the color associated with the observations. Default is "gray"
#' @return displays a individual map for thecorresponding axes and/or sends back a ggplot2 object
NULL
PLNPCAfit$set("public", "plot_individual.map",
  function(axes=c(1,2), main="Individual Factor Map",
           conf.circle = FALSE, conf.level = 0.5, plot=TRUE, cols="gray65", percentAxes=TRUE) {

    .scores <- as.data.frame(self$scores[,axes])
    .scores$labels <- cols
    colnames(.scores) <- paste("a",1:length(axes),sep="")
    cols <- factor(cols)
    axes.label <- paste("axis",axes)
    if (percentAxes)
      axes.label <- paste(axes.label, paste0("(", round(100*self$percentVar,3)[axes], "%)"))

    p <- ggplot(.scores, aes(x=a1, y=a2, label=rownames(self$scores), colour=cols)) +
            geom_hline(yintercept = 0, colour = "gray65") +
            geom_vline(xintercept = 0, colour = "gray65") +
            geom_text(alpha = 0.8, size = 4) +
            ggtitle(main) +
            theme_bw() +
            labs(x=axes.label[1], y=axes.label[2])

    if (conf.circle) {
      uncertainty <- sqrt(self$variational.par$S)
      scaling <- qnorm( (1 - conf.level) / 2)
      p <- p + geom_circle(data = .scores, aes(radius = scaling*uncertainty),
                            alpha = 0.05, colour = cols, fill = cols)
    }

    if (plot)
      print(p)

    invisible(p)
})

#' Plot the correlation circle of a specified axis for a \code{PLNPCAfit} object
#'
#' @name PLNPCAfit_plot_correlation.circle
#' @param axes numeric, the axes to use for the plot. Default it c(1,2)
#' @param main character, the title. Default is "Variable Factor map"
#' @param plot logical. Should the plot be displayed or sent back (ggplot object)
#' @param cols a character, factor or numeric to defined the color associated with the variable. Default is "gray"
#' @param size integer, the size of the labels
#' @return displays a correlation circle for the corresponding axes and/or sends back a ggplot2 object
NULL
PLNPCAfit$set("public", "plot_correlation.circle",
  function(axes=c(1,2), main="Variable Factor Map", cols = "gray65", plot=TRUE, percentAxes=TRUE, size=3) {

    corcir <- circle(c(0, 0), npoints = 100)

    ## data frame with correlations between variables and PCs
    correlations <- as.data.frame(self$corrCircle[, axes])
    p <- nrow(correlations)
    colnames(correlations) <- c("axe1","axe2")
    cols <- factor(cols)
    axes.label <- paste("axis",axes)
    if (percentAxes)
      axes.label <- paste(axes.label, paste0("(", round(100*self$percentVar,3)[axes], "%)"))

    ## data frame with arrows coordinates
    arrows = data.frame(x1 = rep(0, p), y1 = rep(0, p),
                        x2 = correlations$axe1,  y2 = correlations$axe2)

    ## geom_path will do open circles
    p <- ggplot() + geom_path(data = corcir, aes(x=x,y=y), colour="gray65") +
          geom_segment(data = arrows, aes(x = x1, y = y1, xend = x2, yend = y2, colour = cols)) +
          geom_text(data = correlations, aes(x = axe1, y = axe2, label = rownames(correlations), colour=cols), size=size) +
          geom_hline(yintercept = 0, colour = "gray65") + geom_vline(xintercept = 0, colour = "gray65") +
          xlim(-1.1, 1.1) + ylim(-1.1, 1.1)  +
          theme_bw() +  theme(legend.position="none") +
          ggtitle(main) + labs(x=axes.label[1], y=axes.label[2])

    if (plot)
      print(p)

    invisible(p)

})

#' Plot a summary of the current \code{PLNPCAfit} object
#'
#' @name PLNPCAfit_plot
#' @param axes numeric a vector of axes to be considered. The default is 1:min(3,rank).
#' @param plot logical. Should the plot be displayed or sent back (ggplot object)
#' @param cols.ind a character, factor or numeric to define the color associated with the individuals. Default is "gray"
#' @param var.cols a character, factor or numeric to define the color associated with the variables. Default is "gray"
#' @return a plot with a matrix-like layout with size nb.axes x nb.axes, displaying individual maps and correlation circles for the corresponding axes
NULL
PLNPCAfit$set("public", "plot",
  function(cols.ind = "gray", var.cols = "gray", plot=TRUE, axes=1:min(3,self$rank)) {

    nb.axes <- length(axes)
    pairs.axes <- combn(axes, 2, simplify = FALSE)

    ## get back all individual maps
    ind.plot <- lapply(pairs.axes, function(pair) {
      ggobj <- self$plot_individual.map(axes=pair, plot=FALSE, main="", cols=cols.ind, percentAxes=FALSE) + theme(legend.position="none")
      return(ggplotGrob(ggobj))
    })

    ## get back all correlation circle
    cor.plot <- lapply(pairs.axes, function(pair) {
      ggobj <- self$plot_correlation.circle(axes=pair, plot=FALSE, main="", percentAxes=FALSE, cols = var.cols)
      return(ggplotGrob(ggobj))
    })

    ## plot that appear on the diagonal
    criteria.text <- paste("Model Selection\n\n", paste(names(self$criteria), round(self$criteria, 2), sep=" = ", collapse="\n"))
    percentV.text <- paste("Axes contribution\n\n", paste(paste("axis",axes), paste0(": ", round(100*self$percentVar[axes],3), "%"), collapse="\n"))

    diag.grobs <- list(textGrob(percentV.text, just="left"),
                       g_legend(self$plot_individual.map(plot=FALSE, cols=cols.ind) + guides(colour = guide_legend(nrow = 4, title="classification"))),
                       textGrob(criteria.text, just="left"))
    if (nb.axes > 3)
      diag.grobs <- c(diag.grobs, rep(list(nullGrob()), nb.axes-3))


    grobs <- vector("list", nb.axes^2)
    i.cor <- 1; i.ind <- 1; i.dia <- 1
    ind <- 0
    for (i in 1:nb.axes) {
      for (j in 1:nb.axes) {
        ind <- ind+1
        if (j > i) { ## upper triangular  -> cor plot
          grobs[[ind]] <- cor.plot[[i.ind]]
          i.ind <- i.ind + 1
        } else if (i == j) { ## diagonal
          grobs[[ind]] <- diag.grobs[[i.dia]]
          i.dia <- i.dia + 1
        } else {
          grobs[[ind]] <- ind.plot[[i.cor]]
          i.cor <- i.cor + 1
        }
      }
    }
    p <- arrangeGrob(grobs=grobs, ncol=nb.axes)
    if (plot)
      grid.arrange(p)

    invisible(p)
  }
)
