% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/PLNnetworkfamily-class.R
\name{plot.PLNnetworkfamily}
\alias{plot.PLNnetworkfamily}
\title{Display the criteria associated with a collection of PLNnetwork fits (a PLNnetworkfamily)}
\usage{
\method{plot}{PLNnetworkfamily}(x, criteria = c("loglik", "pen_loglik",
  "BIC", "EBIC"), log.x = TRUE, annotate = TRUE, ...)
}
\arguments{
\item{x}{an R6 object with class PLNfamily}

\item{criteria}{vector of characters. The criteria to plot in c("loglik", "BIC", "ICL", "R_squared", "EBIC", "pen_loglik").
Default is  c("loglik", "pen_loglik", "BIC", "EBIC").}

\item{log.x}{logical: should the x-axis be repsented in log-scale? Default is \code{TRUE}.}

\item{annotate}{logical: should the value of approximated R squared be added to the plot? Default is \code{TRUE}.}

\item{...}{additional parameters for S3 compatibility. Not used}
}
\value{
Produces a plot  representing the evolution of the criteria of the different models considered,
highlighting the best model in terms of BIC and EBIC.
}
\description{
Display the criteria associated with a collection of PLNnetwork fits (a PLNnetworkfamily)
}
