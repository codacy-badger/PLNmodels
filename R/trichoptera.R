##' Trichoptera data set
##'
##' Data gathered between 1959 and 1960 during 49 insect trapping nights.
##' For each trapping night, the abundance of 17 Trichoptera
##' species is recorded, which forms the first table.
##' The second table concerns 11 meteorological variables which may influence
##' the abundance of each species. Finally, the observations (that is to say,
##' the trapping nights), have been classified into 12 groups corresponding to
##' contiguous nights between summer 1959 and summer 1960.
##'
##' @format A data frame with 49 rows and 3 variables (matrices):
##' \describe{
##'   \item{Abundance}{a 49 x 17 matrix of abundancies (49 trapping nights and 17 trichoptera species).}
##'   \item{T_max}{Maximal temperature in Celsius}
##'   \item{T_evening}{Evening Temperature in Celsius}
##'   \item{T_min}{Minimal temperature in Celsius}
##'   \item{Wind}{Wind in m/s}
##'   \item{Pressure}{Pressure in mm Hg}
##'   \item{Pressure_range}{Pressure range in mm Hg}
##'   \item{Humidity}{relative to evening humidity in percent}
##'   \item{Cloudiness_night}{proportion of sky coverage at 9pm}
##'   \item{Precipitation_night}{Nighttime precipitation in mm}
##'   \item{Cloudiness_average}{average proportion of sky coverage}
##'   \item{Precipitation_total}{Total precipitation in mm}
##'   \item{Group}{a factor of 12 levels for the definition of the consecutive night groups}
##' }
##' This format is convenient for using formula in multivariate analysis (multiple outputs and inputs).
##'
##' @examples
##' data(trichoptera)
##' str(trichoptera)
##' ## also see the package vignettes
##'
##' @references Usseglio-Polatera, P. and Auda, Y. (1987) Influence des facteurs météorologiques sur les résultats de piégeage lumineux. Annales de Limnologie, 23, 65–79. (code des espèces p. 76)
##' See a data description at \href{http://pbil.univ-lyon1.fr/R/pdf/pps034.pdf}{http://pbil.univ-lyon1.fr/R/pdf/pps034.pdf} (in French)
##' @source Data from P. Usseglio-Polatera.
"trichoptera"

