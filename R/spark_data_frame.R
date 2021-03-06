

#' @export
spark_dataframe.tbl_spark <- function(x, ...) {
  db <- x$src
  con <- db$con

  sql <- as.character(sql_render(sql_build(x, con = con), con = con))
  api <- spark_sql_or_hive(spark_api(x$src))
  invoke(api, "sql", sql)
}

#' @export
spark_dataframe.sparklyr_connection <- function(x, sql = NULL, ...) {
  invoke(spark_sql_or_hive(spark_api(x)), "sql", as.character(sql))
}

spark_dataframe_schema <- function(object) {
  jobj <- spark_dataframe(object)
  schema <- invoke(jobj, "schema")
  fields <- invoke(schema, "fields")
  list <- lapply(fields, function(field) {
    type <- invoke(invoke(field, "dataType"), "toString")
    name <- invoke(field, "name")
    list(name = name, type = type)
  })
  names(list) <- unlist(lapply(list, `[[`, "name"))
  list
}

spark_dataframe_read_column <- function(object, colName) {
  jobj <- spark_dataframe(object)
  schema <- spark_dataframe_schema(jobj)
  colType <- schema[[colName]]$type

  method <- if (colType == "DoubleType")
    "readColumnDouble"
  else if (colType == "IntegerType")
    "readColumnInt"
  else if (colType == "BooleanType")
    "readColumnBoolean"
  else if (colType == "StringType")
    "readColumnString"
  else
    "readColumnDefault"

  sc <- spark_connection(jobj)
  rdd <- jobj %>%
    invoke("select", colName, list()) %>%
    invoke("rdd")

  column <- invoke_static(sc, "utils", method, rdd)

  if (colType == "StringType") {

    df <- readr::read_csv(
      column,
      col_names = FALSE,
      col_types = "c",
      na = character(),
      trim_ws = FALSE,
      progress = FALSE
    )

    column <- df[[1]]
    Encoding(column) <- "UTF-8"
  }

  column
}

# Read a Spark Dataset into R.
spark_dataframe_collect <- function(object) {
  jobj <- spark_dataframe(object)
  schema <- spark_dataframe_schema(jobj)
  colNames <- as.character(invoke(jobj, "columns"))
  colValues <- lapply(schema, function(colInfo) {
    spark_dataframe_read_column(jobj, colInfo$name)
  })

  df <- lapply(colValues, unlist, recursive = FALSE)
  names(df) <- colNames
  dplyr::as_data_frame(df, stringsAsFactors = FALSE, optional = TRUE)
}

# Split a Spark DataFrame
spark_dataframe_split <- function(object,
                                  weights = c(0.5, 0.5),
                                  seed = sample(.Machine$integer.max, 1))
{
  jobj <- spark_dataframe(object)
  invoke(jobj, "randomSplit", as.list(weights), as.integer(seed))
}

