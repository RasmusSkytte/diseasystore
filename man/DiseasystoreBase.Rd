% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/DiseasystoreBase.R
\name{DiseasystoreBase}
\alias{DiseasystoreBase}
\title{diseasystore base handler}
\value{
A new instance of the \code{DiseasystoreBase} \link[R6:R6Class]{R6} class.
}
\description{
This \code{DiseasystoreBase} \link[R6:R6Class]{R6} class forms the basis of all feature stores.
It defines the primary methods of each feature stores as well as all of the public methods.
}
\examples{
  # DiseasystoreBase is mostly used as the basis of other, more specific, classes
  # The DiseasystoreBase can be initialized individually if needed.

  ds <- DiseasystoreBase$new(source_conn = NULL,
                             target_conn = DBI::dbConnect(RSQLite::SQLite()))

}
\section{Active bindings}{
\if{html}{\out{<div class="r6-active-bindings">}}
\describe{
\item{\code{fs_map}}{(\verb{named list}(\code{character}))\cr
A list that maps features known by the feature store to the corresponding feature handlers
that compute the features. Read only.}

\item{\code{available_features}}{(\code{character})\cr
A list of available features in the feature store. Read only.}

\item{\code{case_definition}}{(\code{character})\cr
A human readable case_definition of the feature store. Read only.}

\item{\code{source_conn}}{source_conn\cr Used to specify where data is located.  Read only. Can be \code{DBIConnection} or file path depending on the \code{diseasystore}.}

\item{\code{target_conn}}{target_conn (\code{DBIConnection})\cr A database connection to store the computed features in.  Read only.}

\item{\code{target_schema}}{target_schema (\code{character})\cr The schema to place the feature store in.  Read only. If the database backend does not support schema, the tables will be prefixed with target_schema.}

\item{\code{start_date}}{start_date (\code{Date})\cr Study period start.  Read only.}

\item{\code{end_date}}{end_date (\code{Date})\cr Study period end.  Read only.}

\item{\code{slice_ts}}{slice_ts (\code{Date} or \code{character})\cr Date to slice the database on (used if source_conn is a database).  Read only.}
}
\if{html}{\out{</div>}}
}
\section{Methods}{
\subsection{Public methods}{
\itemize{
\item \href{#method-DiseasystoreBase-new}{\code{DiseasystoreBase$new()}}
\item \href{#method-DiseasystoreBase-finalize}{\code{DiseasystoreBase$finalize()}}
\item \href{#method-DiseasystoreBase-get_feature}{\code{DiseasystoreBase$get_feature()}}
\item \href{#method-DiseasystoreBase-key_join_features}{\code{DiseasystoreBase$key_join_features()}}
\item \href{#method-DiseasystoreBase-key_join_filter}{\code{DiseasystoreBase$key_join_filter()}}
\item \href{#method-DiseasystoreBase-clone}{\code{DiseasystoreBase$clone()}}
}
}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-DiseasystoreBase-new"></a>}}
\if{latex}{\out{\hypertarget{method-DiseasystoreBase-new}{}}}
\subsection{Method \code{new()}}{
Creates a new instance of the \code{DiseasystoreBase} \link[R6:R6Class]{R6} class.
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{DiseasystoreBase$new(
  start_date = NULL,
  end_date = NULL,
  slice_ts = NULL,
  source_conn = NULL,
  target_conn = NULL,
  target_schema = NULL,
  verbose = TRUE
)}\if{html}{\out{</div>}}
}

\subsection{Arguments}{
\if{html}{\out{<div class="arguments">}}
\describe{
\item{\code{start_date}}{start_date (\code{Date})\cr Study period start.}

\item{\code{end_date}}{end_date (\code{Date})\cr Study period end.}

\item{\code{slice_ts}}{slice_ts (\code{Date} or \code{character})\cr Date to slice the database on (used if source_conn is a database).}

\item{\code{source_conn}}{source_conn\cr Used to specify where data is located.  Can be \code{DBIConnection} or file path depending on the \code{diseasystore}.}

\item{\code{target_conn}}{target_conn (\code{DBIConnection})\cr A database connection to store the computed features in.}

\item{\code{target_schema}}{target_schema (\code{character})\cr The schema to place the feature store in.  If the database backend does not support schema, the tables will be prefixed with target_schema.}

\item{\code{verbose}}{(\code{boolean})\cr
Boolean that controls enables debugging information.}
}
\if{html}{\out{</div>}}
}
\subsection{Returns}{
A new instance of the \code{DiseasystoreBase} \link[R6:R6Class]{R6} class.
}
}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-DiseasystoreBase-finalize"></a>}}
\if{latex}{\out{\hypertarget{method-DiseasystoreBase-finalize}{}}}
\subsection{Method \code{finalize()}}{
Closes the open DB connection when removing the object
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{DiseasystoreBase$finalize()}\if{html}{\out{</div>}}
}

}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-DiseasystoreBase-get_feature"></a>}}
\if{latex}{\out{\hypertarget{method-DiseasystoreBase-get_feature}{}}}
\subsection{Method \code{get_feature()}}{
Computes, stores, and returns the requested feature for the study period.
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{DiseasystoreBase$get_feature(
  feature,
  start_date = self \%.\% start_date,
  end_date = self \%.\% end_date,
  slice_ts = self \%.\% slice_ts
)}\if{html}{\out{</div>}}
}

\subsection{Arguments}{
\if{html}{\out{<div class="arguments">}}
\describe{
\item{\code{feature}}{(\code{character})\cr
The name of a feature defined in the feature store.}

\item{\code{start_date}}{start_date (\code{Date})\cr Study period start.}

\item{\code{end_date}}{end_date (\code{Date})\cr Study period end.}

\item{\code{slice_ts}}{slice_ts (\code{Date} or \code{character})\cr Date to slice the database on (used if source_conn is a database).}
}
\if{html}{\out{</div>}}
}
\subsection{Returns}{
A tbl_dbi with the requested feature for the study period.
}
}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-DiseasystoreBase-key_join_features"></a>}}
\if{latex}{\out{\hypertarget{method-DiseasystoreBase-key_join_features}{}}}
\subsection{Method \code{key_join_features()}}{
Joins various features from feature store assuming a primary feature (observable)
that contains keys to witch the secondary features (defined by aggregation) can be joined.
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{DiseasystoreBase$key_join_features(
  observable,
  aggregation,
  start_date = self \%.\% start_date,
  end_date = self \%.\% end_date
)}\if{html}{\out{</div>}}
}

\subsection{Arguments}{
\if{html}{\out{<div class="arguments">}}
\describe{
\item{\code{observable}}{(\code{character})\cr
The name of a feature defined in the feature store}

\item{\code{aggregation}}{(\code{list}(\code{quosures}))\cr
Expressions in aggregation evaluated to find appropriate features.
These are then joined to the observable feature before aggregation is performed.}

\item{\code{start_date}}{start_date (\code{Date})\cr Study period start.}

\item{\code{end_date}}{end_date (\code{Date})\cr Study period end.}
}
\if{html}{\out{</div>}}
}
\subsection{Returns}{
A tbl_dbi with the requested joined features for the study period.
}
}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-DiseasystoreBase-key_join_filter"></a>}}
\if{latex}{\out{\hypertarget{method-DiseasystoreBase-key_join_filter}{}}}
\subsection{Method \code{key_join_filter()}}{
This function implements an intermediate filtering in the aggregation pipeline.
For semi-aggregated data like Googles COVID-19 data, some people are counted more than once.
The \code{key_join_filter} is inserted into the aggregation pipeline to remove this double counting.
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{DiseasystoreBase$key_join_filter(
  .data,
  aggregation_features,
  start_date = self \%.\% start_date,
  end_date = self \%.\% end_date
)}\if{html}{\out{</div>}}
}

\subsection{Arguments}{
\if{html}{\out{<div class="arguments">}}
\describe{
\item{\code{.data}}{.data\cr The data object to perform the operation on}

\item{\code{aggregation_features}}{(\code{character})\cr
A list of the features included in the aggregation process.}

\item{\code{start_date}}{start_date (\code{Date})\cr Study period start.}

\item{\code{end_date}}{end_date (\code{Date})\cr Study period end.}
}
\if{html}{\out{</div>}}
}
\subsection{Returns}{
A subset of \code{.data} filtered to remove double counting
}
}
\if{html}{\out{<hr>}}
\if{html}{\out{<a id="method-DiseasystoreBase-clone"></a>}}
\if{latex}{\out{\hypertarget{method-DiseasystoreBase-clone}{}}}
\subsection{Method \code{clone()}}{
The objects of this class are cloneable with this method.
\subsection{Usage}{
\if{html}{\out{<div class="r">}}\preformatted{DiseasystoreBase$clone(deep = FALSE)}\if{html}{\out{</div>}}
}

\subsection{Arguments}{
\if{html}{\out{<div class="arguments">}}
\describe{
\item{\code{deep}}{Whether to make a deep clone.}
}
\if{html}{\out{</div>}}
}
}
}
