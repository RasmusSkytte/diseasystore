#' @title diseasystore base handler
#'
#' @description
#'   This `DiseasystoreBase` [R6][R6::R6Class] class forms the basis of all feature stores.
#'   It defines the primary methods of each feature stores as well as all of the public methods.
#' @examples
#'   # DiseasystoreBase is mostly used as the basis of other, more specific, classes
#'   # The DiseasystoreBase can be initialized individually if needed.
#'
#'   ds <- DiseasystoreBase$new(source_conn = NULL,
#'                              target_conn = DBI::dbConnect(RSQLite::SQLite()))
#'
#' @return
#'   A new instance of the `DiseasystoreBase` [R6][R6::R6Class] class.
#' @export
DiseasystoreBase <- R6::R6Class( # nolint: object_name_linter.
  classname = "DiseasystoreBase",

  public = list(

    #' @description
    #'   Creates a new instance of the `DiseasystoreBase` [R6][R6::R6Class] class.
    #' @param start_date `r rd_start_date()`
    #' @param end_date `r rd_end_date()`
    #' @param slice_ts `r rd_slice_ts()`
    #' @param source_conn `r rd_source_conn()`
    #' @param target_conn `r rd_target_conn()`
    #' @param target_schema `r rd_target_schema()`
    #' @param verbose (`boolean`)\cr
    #'   Boolean that controls enables debugging information.
    #' @return
    #'   A new instance of the `DiseasystoreBase` [R6][R6::R6Class] class.
    initialize = function(start_date = NULL, end_date = NULL, slice_ts = NULL,
                          source_conn = NULL, target_conn = NULL, target_schema = NULL,
                          verbose = TRUE) {

      # Validate input
      coll <- checkmate::makeAssertCollection()
      checkmate::assert_date(start_date, null.ok = TRUE, add = coll)
      checkmate::assert_date(end_date, null.ok = TRUE,   add = coll)
      checkmate::assert_character(slice_ts, pattern = r"{\d{4}-\d{2}-\d{2}(<? \d{2}:\d{2}:\d{2})}",
                                  null.ok = TRUE, add = coll)
      checkmate::assert_logical(verbose, add = coll)
      checkmate::reportAssertions(coll)

      # Set internals
      if (!is.null(slice_ts))   private$.slice_ts   <- slice_ts
      if (!is.null(start_date)) private$.start_date <- start_date
      if (!is.null(end_date))   private$.end_date   <- end_date
      private$verbose <- verbose

      # Set the internal paths
      if (is.null(source_conn)) {
        private$.source_conn <- parse_diseasyconn(diseasyoption("source_conn", self))
      } else {
        private$.source_conn <- source_conn
      }

      if (is.null(target_conn)) {
        private$.target_conn <- parse_diseasyconn(diseasyoption("target_conn", self))
      } else {
        private$.target_conn <- target_conn
      }


      # Check source and target conn has been set correctly
      if (is.null(self %.% source_conn)) stop("source_conn option not defined for ", class(self)[1])
      if (is.null(self %.% target_conn)) stop("target_conn option not defined for ", class(self)[1])
      checkmate::assert_class(self %.% target_conn, "DBIConnection")


      if (is.null(target_schema)) {
        private$.target_schema <- diseasyoption("target_schema", self)
        if (is.null(self %.% target_schema)) {
          private$.target_schema <- "ds" # Default to "ds"
        }
      } else {
        private$.target_schema <- target_schema
      }
      checkmate::assert_character(self %.% target_schema)

      # Initialize the feature handlers
      private$initialize_feature_handlers()
    },


    #' @description
    #'   Closes the open DB connection when removing the object
    finalize = function() {
      purrr::walk(list(self %.% target_conn, self %.% source_conn),
                  ~ if (inherits(., "DBIConnection") && !inherits(., "TestConnection") && DBI::dbIsValid(.)) {
                    DBI::dbDisconnect(.)
                  })
    },


    #' @description
    #'   Computes, stores, and returns the requested feature for the study period.
    #' @param feature (`character`)\cr
    #'   The name of a feature defined in the feature store.
    #' @param start_date `r rd_start_date()`
    #' @param end_date `r rd_end_date()`
    #' @param slice_ts `r rd_slice_ts()`
    #' @return
    #'   A tbl_dbi with the requested feature for the study period.
    get_feature = function(feature,
                           start_date = self %.% start_date,
                           end_date   = self %.% end_date,
                           slice_ts   = self %.% slice_ts) {

      # Load the available features
      fs_map <- self %.% fs_map

      # Validate input
      coll <- checkmate::makeAssertCollection()
      checkmate::assert_choice(feature, unlist(fs_map), add = coll)
      checkmate::assert_date(start_date, any.missing = FALSE, add = coll)
      checkmate::assert_date(end_date,   any.missing = FALSE, add = coll)
      checkmate::assert_character(slice_ts, pattern = r"{\d{4}-\d{2}-\d{2}(<? \d{2}:\d{2}:\d{2})}", add = coll)
      checkmate::assert(!is.null(self %.% source_conn), add = coll)
      checkmate::assert(!is.null(self %.% target_conn), add = coll)
      checkmate::reportAssertions(coll)

      # Determine which feature_loader should be called
      feature_loader <- names(fs_map[fs_map == feature])

      # Create log table
      SCDB::create_logs_if_missing(log_table = paste(c(self %.% target_schema, "logs"), collapse = "."),
                                   conn = self %.% target_conn)

      # Determine which dates need to be computed
      target_table <- paste(c(self %.% target_schema, feature_loader), collapse = ".")

      fs_missing_ranges <- private$determine_new_ranges(target_table = target_table,
                                                        start_date = start_date,
                                                        end_date   = end_date,
                                                        slice_ts   = slice_ts)

      # Inform that we are computing features
      tic <- Sys.time()
      if (private %.% verbose && nrow(fs_missing_ranges) > 0) {
        message(glue::glue("feature: {feature} needs to be computed on the specified date interval. ",
                           "please wait..."))
      }

      # Call the feature loader on the dates
      purrr::pwalk(fs_missing_ranges, ~ {

        start_date <- ..1
        end_date   <- ..2

        # Compute the feature for the date range
        fs_feature <- do.call(what = purrr::pluck(private, feature_loader) %.% compute,
                              args = list(start_date = start_date, end_date = end_date,
                                          slice_ts = slice_ts, source_conn = self %.% source_conn))

        # Check it table is copied to target DB
        if (!inherits(fs_feature, "tbl_dbi") ||
              !identical(self %.% source_conn, self %.% target_conn)) {
          fs_feature <- dplyr::copy_to(self %.% target_conn, fs_feature, "fs_tmp", overwrite = TRUE)
        }

        # Add the existing computed data for given slice_ts
        if (SCDB::table_exists(self %.% target_conn, target_table)) {
          fs_existing <- dplyr::tbl(self %.% target_conn, SCDB::id(target_table, self %.% target_conn))

          if (SCDB::is.historical(fs_existing)) {
            fs_existing <- fs_existing |>
              dplyr::filter(.data$from_ts == slice_ts) |>
              dplyr::select(!tidyselect::all_of(c("checksum", "from_ts", "until_ts"))) |>
              dplyr::filter(.data$valid_until < start_date, .data$valid_from < end_date)
          }

          fs_updated_feature <- dplyr::union_all(fs_existing, fs_feature) |> dplyr::compute()
        } else {
          fs_updated_feature <- fs_feature
        }

        # Commit to DB
        capture.output({
          SCDB::update_snapshot(
            .data = fs_updated_feature,
            conn = self %.% target_conn,
            db_table = target_table,
            timestamp = slice_ts,
            message = glue::glue("fs-range: {start_date} - {end_date}"),
            logger = SCDB::Logger$new(output_to_console = FALSE,
                                      log_table_id = paste(c(self %.% target_schema, "logs"), collapse = "."),
                                      log_conn = self %.% target_conn),
            enforce_chronological_order = FALSE
          )
        })
      })

      # Inform how long has elapsed for updating data
      if (private$verbose && nrow(fs_missing_ranges) > 0) {
        message(glue::glue("feature: {feature} updated ",
                           "(elapsed time {format(round(difftime(Sys.time(), tic)),2)})."))
      }

      # Finally, return the data to the user
      out <- do.call(what = purrr::pluck(private, feature_loader) %.% get,
                     args = list(target_table = target_table,
                                 slice_ts = slice_ts, target_conn = self %.% target_conn))

      # We need to slice to the period of interest.
      # to ensure proper conversion of variables, we first copy the limits over and then do an inner_join
      dplyr::inner_join(out,
                        data.frame(valid_from = start_date, valid_until = end_date) %>%
                          dplyr::copy_to(self %.% target_conn, ., "fs_tmp", overwrite = TRUE),
                        sql_on = '"LHS"."valid_from" <= "RHS"."valid_until" AND
                                  ("LHS"."valid_until" > "RHS"."valid_from" OR "LHS"."valid_until" IS NULL)',
                        suffix = c("", ".p")) |>
        dplyr::select(!c("valid_from.p", "valid_until.p"))

    },

    #' @description
    #'   Joins various features from feature store assuming a primary feature (observable)
    #'   that contains keys to witch the secondary features (defined by aggregation) can be joined.
    #' @param observable (`character`)\cr
    #'   The name of a feature defined in the feature store
    #' @param aggregation (`list`(`quosures`))\cr
    #'   Expressions in aggregation evaluated to find appropriate features.
    #'   These are then joined to the observable feature before aggregation is performed.
    #' @param start_date `r rd_start_date()`
    #' @param end_date `r rd_end_date()`
    #' @return
    #'   A tbl_dbi with the requested joined features for the study period.
    key_join_features = function(observable, aggregation,
                                 start_date = self %.% start_date,
                                 end_date   = self %.% end_date) {

      # Validate input
      available_observables  <- self$available_features |>
        purrr::keep(~ startsWith(., "n_") | endsWith(., "_temperature"))
      available_aggregations <- self$available_features |>
        purrr::discard(~ startsWith(., "n_") | endsWith(., "_temperature"))

      coll <- checkmate::makeAssertCollection()
      checkmate::assert_choice(observable, available_observables, add = coll)
      checkmate::assert(
        checkmate::check_choice(aggregation, available_aggregations, null.ok = TRUE),
        checkmate::check_class(aggregation, "quosure", null.ok = TRUE),
        checkmate::check_class(aggregation, "quosures", null.ok = TRUE),
        add = coll
      )
      checkmate::assert_date(start_date, add = coll)
      checkmate::assert_date(end_date, add = coll)
      checkmate::reportAssertions(coll)

      # Store the fs_map
      fs_map <- self %.% fs_map

      # We start by copying the study_dates to the conn to ensure SQLite compatibility
      study_dates <- data.frame(valid_from = start_date, valid_until = end_date + lubridate::days(1)) %>%
        dplyr::copy_to(self %.% target_conn, ., overwrite = TRUE)

      # Determine which features are affected by an aggregation
      if (!is.null(aggregation)) {

        # Create regex detection for features
        fs_map_regex <- paste0(r"{(?<=^|\W)}", fs_map, r"{(?=$|\W)}")

        # Perform detection of features in the aggregation
        aggregation_features <- purrr::map(aggregation, rlang::as_label) |>
          purrr::map(\(e) unlist(fs_map[purrr::map_lgl(fs_map_regex, ~ stringr::str_detect(e, .x))])) |>
          unlist() |>
          unique()

        # Report if aggregation not found
        if (is.null(aggregation_features)) {
          err <- glue::glue("Aggregation variable not found. ",
                            "Available aggregation variables are: ",
                            "{toString(available_aggregations)}")
          stop(err)
        }

        aggregation_names <- purrr::map(aggregation, rlang::as_label)
        aggregation_names <- purrr::map2_chr(aggregation_names,
                                             names(aggregation_names),
                                             ~ ifelse(.y == "", .x, .y)) |>
          unname()

        # Check aggregation features are not observables
        stopifnot("Aggregation features cannot be observables" =
                    purrr::none(aggregation_names, ~ . %in% available_observables))

        # Fetch requested aggregation features from the feature store
        aggregation_data <- aggregation_features |>
          unique() |>
          purrr::map(~ {
            # Fetch the requested aggregation feature from the feature store and truncate to the start
            #  and end dates to simplify the interlaced output
            self$get_feature(.x, start_date, end_date) |>
              dplyr::cross_join(study_dates, suffix = c("", ".d")) |>
              dplyr::mutate("valid_from" = pmax(.data$valid_from, .data$valid_from.d, na.rm = TRUE),
                            "valid_until" =
                              dplyr::coalesce(pmin(.data$valid_until, .data$valid_until.d, na.rm = TRUE),
                                              .data$valid_until.d)) |>
              dplyr::select(!ends_with(".d"))
          })
      } else {
        aggregation_features <- NULL
        aggregation_names <- NULL
        aggregation_data <- NULL
      }

      # Fetch the requested observable from the feature store and truncate to the start and end dates
      # to simplify the interlaced output
      observable_data <- self$get_feature(observable, start_date, end_date) |>
        dplyr::cross_join(study_dates, suffix = c("", ".d")) |>
        dplyr::mutate("valid_from" = pmax(.data$valid_from, .data$valid_from.d, na.rm = TRUE),
                      "valid_until" =
                        dplyr::coalesce(pmin(.data$valid_until, .data$valid_until.d, na.rm = TRUE),
                                        .data$valid_until.d)) |>
        dplyr::select(!ends_with(".d"))

      # Determine the keys
      observable_keys  <- colnames(dplyr::select(observable_data, tidyselect::starts_with("key_")))

      # Map aggregation_data to observable_keys (if not already)
      if (!is.null(aggregation_data)) {
        aggregation_keys <- purrr::map(aggregation_data, ~ colnames(dplyr::select(., tidyselect::starts_with("key_"))))

        aggregation_data <- aggregation_data |>
          purrr::map_if(!purrr::map_lgl(aggregation_keys, ~ any(observable_keys %in% .)),
                        ~ .) # TODO: create the mapping
      }

      # Merge and prepare for counting
      out <- truncate_interlace(observable_data, aggregation_data) |>
        self$key_join_filter(aggregation_features, start_date, end_date) |>
        dplyr::compute() |>
        dplyr::group_by(!!!aggregation)

      # Retrieve the aggregators (and ensure they work together)
      key_join_aggregators <- c(purrr::pluck(private, names(fs_map[fs_map == observable])) %.% key_join,
                                purrr::map(aggregation_features,
                                           ~ purrr::pluck(private, names(fs_map)[fs_map == .x]) %.% key_join))

      if (length(unique(key_join_aggregators)) > 1) {
        stop("(At least one) aggregation feature does not match observable aggregator. Not implemented yet.")
      }

      key_join_aggregator <- purrr::pluck(key_join_aggregators, 1)

      # Add the new valid counts
      t_add <- out |>
        dplyr::group_by(date = valid_from, .add = TRUE) |>
        key_join_aggregator(observable) |>
        dplyr::rename(n_add = n) |>
        dplyr::compute()

      # Add the new invalid counts
      t_remove <- out |>
        dplyr::group_by(date = valid_until, .add = TRUE) |>
        key_join_aggregator(observable) |>
        dplyr::rename(n_remove = n) |>
        dplyr::compute()

      # Get all combinations to merge onto
      all_dates <- tibble::tibble(date = seq.Date(from = start_date, to = end_date, by = 1))

      if (!is.null(aggregation)) {
        all_combi <- out |>
          dplyr::ungroup() |>
          dplyr::distinct(!!!aggregation) |>
          dplyr::cross_join(all_dates, copy = TRUE) |>
          dplyr::compute()
      } else {
        all_combi <- all_dates
      }

      # Aggregate across dates
      data <- t_add |>
        dplyr::right_join(all_combi, by = c("date", aggregation_names), na_matches = "na",
                          copy = is.null(aggregation)) |>
        dplyr::left_join(t_remove,  by = c("date", aggregation_names), na_matches = "na") |>
        tidyr::replace_na(list(n_add = 0, n_remove = 0)) |>
        dplyr::group_by(tidyselect::across(tidyselect::all_of(aggregation_names))) |>
        dbplyr::window_order(date) |>
        dplyr::mutate(date, !!observable := cumsum(n_add) - cumsum(n_remove)) |>
        dplyr::ungroup() |>
        dplyr::select(date, all_of(aggregation_names), !!observable) |>
        dplyr::collect()

      return(data)
    },


    #' @description
    #'   This function implements an intermediate filtering in the aggregation pipeline.
    #'   For semi-aggregated data like Googles COVID-19 data, some people are counted more than once.
    #'   The `key_join_filter` is inserted into the aggregation pipeline to remove this double counting.
    #' @param .data `r rd_.data()`
    #' @param aggregation_features (`character`)\cr
    #'   A list of the features included in the aggregation process.
    #' @param start_date `r rd_start_date()`
    #' @param end_date `r rd_end_date()`
    #' @return
    #'   A subset of `.data` filtered to remove double counting
    key_join_filter = function(.data, aggregation_features,
                               start_date = self %.% start_date,
                               end_date   = self %.% end_date) {
      return(.data) # By default, no filtering is performed
    }
  ),

  active = list(

    #' @field fs_map (`named list`(`character`))\cr
    #'   A list that maps features known by the feature store to the corresponding feature handlers
    #'   that compute the features. Read only.
    fs_map = purrr::partial(
      .f = active_binding, # nolint start: indentation_linter
      name = "fs_map",
      expr = {  # nolint: indentation_linter
        # Generic features are named generic_ in the db
        fs_generic <- private %.% fs_generic
        if (!is.null(fs_generic)) names(fs_generic) <- paste("generic", names(fs_generic), sep = "_")

        # Specific features are named by the case definition of the feature store
        fs_specific <- private %.% fs_specific
        if (!is.null(fs_specific)) {

          # We need to transform case definition to snake case
          fs_case_definition <- self$case_definition |>
            stringr::str_to_lower() |>
            stringr::str_replace_all(" ", "_") |>
            stringr::str_replace_all("-", "_")


          # Then we can paste it together
          names(fs_specific) <- names(fs_specific) |>
            purrr::map_chr(~ glue::glue_collapse(sep = "_",
                                                 x = c(fs_case_definition, .x)))
        }

        return(c(fs_generic, fs_specific))
      }), # nolint end


    #' @field available_features (`character`)\cr
    #'   A list of available features in the feature store. Read only.
    available_features = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "available_features",
      expr = return(unlist(self$fs_map, use.names = FALSE))),


    #' @field case_definition (`character`)\cr
    #'   A human readable case_definition of the feature store. Read only.
    case_definition = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "case_definition",
      expr = return(private$.case_definition)),


    #' @field source_conn `r rd_source_conn("field")`
    source_conn = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "source_conn",
      expr = {
        if (!is.null(private$.source_conn)) {
          return(private$.source_conn)
        } else {
          return(private$.target_conn)
        }
      }),


    #' @field target_conn `r rd_target_conn("field")`
    target_conn = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "target_conn",
      expr = return(private$.target_conn)),


    #' @field target_schema `r rd_target_schema("field")`
    target_schema = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "target_schema",
      expr = return(private$.target_schema)),


    #' @field start_date `r rd_start_date("field")`
    start_date = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "start_date",
      expr = return(private$.start_date)),


    #' @field end_date `r rd_end_date("field")`
    end_date = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "end_date",
      expr = return(private$.end_date)),


    #' @field slice_ts `r rd_slice_ts("field")`
    slice_ts = purrr::partial(
      .f = active_binding, # nolint: indentation_linter
      name = "slice_ts",
      expr = return(private$.slice_ts))
  ),

  private = list(

    .case_definition = NULL,
    .source_conn     = NULL,
    .target_conn     = NULL,
    .target_schema   = NULL,

    .start_date = NULL,
    .end_date   = NULL,
    .slice_ts   = glue::glue("{lubridate::today() - lubridate::days(1)} 09:00:00"),

    fs_generic  = NULL, # Must be implemented in child classes
    fs_specific = NULL, # Must be implemented in child classes
    fs_key_map  = NULL, # Must be implemented in child classes



    verbose = TRUE,

    determine_new_ranges = function(target_table, start_date, end_date, slice_ts) {

      # Get a list of the logs for the target_table on the slice_ts
      logs <- dplyr::tbl(self %.% target_conn,
                         SCDB::id(paste(c(self %.% target_schema, "logs"), collapse = "."), self %.% target_conn)) |>
        dplyr::collect() |>
        tidyr::unite("target_table", "schema", "table", sep = ".", na.rm = TRUE) |>
        dplyr::filter(target_table == !!target_table, date == !!slice_ts)

      # If no logs are found, we need to compute on the entire range
      if (nrow(logs) == 0) {
        return(tibble::tibble(start_date = start_date, end_date = end_date))
      }

      # Determine the date ranges used
      logs <- logs |>
        dplyr::mutate(fs_start_date = stringr::str_extract(message, "(?<=fs-range: )([0-9]{4}-[0-9]{2}-[0-9]{2})"),
                      fs_end_date   = stringr::str_extract(message, "([0-9]{4}-[0-9]{2}-[0-9]{2})$")) |>
        dplyr::mutate(across(.cols = c("fs_start_date", "fs_end_date"), .fns = as.Date))

      # Find updates that overlap with requested range
      logs <- logs |>
        dplyr::filter(fs_start_date < end_date, start_date <= fs_end_date)

      # Looks for updates that (potentially) are ongoing
      potentially_ongoing <- logs |>
        dplyr::mutate(duration = as.numeric(difftime(Sys.time(), start_time, unit = "mins"))) |>
        dplyr::filter(is.na(success) & duration < 30) |>
        dplyr::select(message, duration)

      if (nrow(potentially_ongoing) > 0) {
        err <- glue::glue("db: {target_table} is potentially being updated on the specified date interval. ",
                          "Aborting...")
        cat(err)

        potentially_ongoing |>
          purrr::pmap(~ printr(glue::glue("{..1} started updating {round(..2)} minutes ago. ",
                                          "Releasing lock after 30 minutes")))
        stop(err)
      }

      # Determine the dates covered on this slice_ts
      if (SCDB::nrow(logs) > 0) {
        fs_dates <- logs |>
          dplyr::select(fs_start_date, fs_end_date) |>
          purrr::pmap(\(fs_start_date, fs_end_date) seq.Date(from = as.Date(fs_start_date),
                                                             to = as.Date(fs_end_date),
                                                             by = "1 day")) |>
          purrr::reduce(dplyr::union_all) |> # union does not preserve type (converts from Date to numeric)
          unique() # so we have to use union_all (preserves type) followed by unique (preserves type)
      } else {
        fs_dates <- list()
      }

      # Define the new dates to compute
      new_interval <- seq.Date(from = as.Date(start_date), to = as.Date(end_date), by = "1 day")

      # Determine the dates that needs to be computed
      new_dates <- zoo::as.Date(setdiff(new_interval, fs_dates))
      # setdiff does not preserve type (converts from Date to numeric)
      # it even breaks the type so hard, that we need to supply the origin also (which for some reason is not default)
      # so we use the zoo::as.Date, since this is reasonably configured...

      # Early return, if no new dates are found
      if (length(new_dates) == 0) {
        return(tibble::tibble(start_date = as.Date(character(0)), end_date = as.Date(character(0))))
      }

      # Reduce to single intervals
      new_ranges <- tibble::tibble(date = new_dates) |>
        dplyr::mutate(next_date_diff = as.numeric(difftime(dplyr::lead(.data$date), .data$date, units = "days")),
                      prev_date_diff = as.numeric(difftime(.data$date, dplyr::lag(.data$date), units = "days")),
                      first_in_segment = dplyr::if_else(is.na(next_date_diff) | next_date_diff > 1, FALSE, TRUE) |
                                           dplyr::if_else(is.na(prev_date_diff) | prev_date_diff > 1, TRUE, FALSE)) |> # nolint: indentation_linter
        dplyr::group_by(cumsum(.data$first_in_segment)) |>
        dplyr::summarise(start_date = min(.data$date, na.rm = TRUE),
                         end_date   = max(.data$date, na.rm = TRUE),
                         .groups = "drop") |>
        dplyr::select(start_date, end_date)

      return(new_ranges)
    },

    initialize_feature_handlers = function() NULL
  )
)

# Set default options for the package related to the Google COVID-19 store
rlang::on_load({
  options(diseasystore.source_conn = "")
  options(diseasystore.target_conn = "")
  options(diseasystore.target_schema = "")
})
