# Shiny app to summarize usage data at the IMPALA
# Process JSON exports from eLabFTW
# Written by Ivan Calandra

###############################################################################################################


#####################
# 1. Load libraries #
#####################

library(ggplot2)
library(mark)
library(readODS)
library(rjson)
library(shiny)
library(tidyverse)
library(writexl)


###############################################################################################################


################
# 2. Define UI #
################

ui <- fluidPage(

  # 2.1. Application title
  titlePanel("Create a report for your microscope images acquired at the Imaging Platform At LEIZA (IMPALA)"),

  sidebarLayout(

    # 2.2. Sidebar
    sidebarPanel(

      # upload JSON file
      fileInput("JSONfile", "Choose JSON File (exported from eLabFTW)",
                multiple = FALSE, accept = ".json"),

      # LEIZA logo
      img(src = "Leiza_Logo_Deskriptor_CMYK_rot_LEIZA.png", height = 150),

      # Credit
      splitLayout(cellWidths = c("50%", "50%"),
                  h5("By Ivan Calandra"),
                  actionButton("GitHub", "user-count_App",
                               icon = icon("github", lib = "font-awesome"),
                               onclick = "window.open('https://github.com/ivan-paleo/user-count_App', '_blank')")),

      # Version number / date - ADJUST WITH NEW VERSION / DATE
      h5("v0.1 (2025-12-02)"),

      # Set minimum size of elements in the sidebar
      tags$head(
        tags$style(type = "text/css", "select { min-width: 350px; }"),
        tags$style(type = "text/css", ".span4 { min-width: 350px; }"),
        tags$style(type = "text/css", "textarea { min-width: 350px; }"),
        tags$style(type = "text/css", ".jslider { min-width: 350px; }"),
        tags$style(type = "text/css", ".well { min-width: 350px; }")
      )
    ),

    # 2.3. Main panel
    mainPanel(

      # Tabs
      tabsetPanel(type = "tabs",

        # Tabs, their UIs will be rendered in the server call below
        tabPanel("All experiments", fluidRow(
          h2("All experiments sorted by PI"),
          tableOutput("exp"),
          downloadButton("downloadExpXLSX", "Download to XLSX"),
          downloadButton("downloadExpODS", "Download to ODS")
        )),

        tabPanel("PI", fluidRow(
          h2("Number of experiments for each PI"),
          tableOutput("PI"),
          downloadButton("downloadPIXLSX", "Download to XLSX"),
          downloadButton("downloadPIODS", "Download to ODS")
        )),

        tabPanel("Experiments over time", fluidRow(
          h2("Number of experiments over time"),
          plotOutput("time"),
          downloadButton("downloadTimePDF", "Download to PDF"),
          downloadButton("downloadTimePNG", "Download to PNG"),
        ))
      )
    )
  )
)


###############################################################################################################


##########################
# 3. Define server logic #
##########################

server <- function(input, output) {

  # 3.1 Read and format data
  # Use reactive() to use input file
  experiments <- reactive({

    # Ensure that file has been uploaded before proceeding
    req(input$JSONfile)

    # Read uploaded JSON file
    experiments <- fromJSON(file = input$JSONfile$datapath)

    # Extract PI names and dates of scans
    PI <- sapply(experiments, FUN = function(x) c(x[["metadata_decoded"]][["extra_fields"]][["PI"]][["value"]]))
    Scan_date <- sapply(experiments, FUN = function(x) c(x[["date"]]))
    equip <- sapply(experiments, FUN = function(x) c(x[["items_links"]][[1]][["title"]]))
    table_users <- data.frame(PI = PI, Date = Scan_date, Instrument = equip)  %>%
                   arrange(PI)
    return(table_users)
  })


  # 3.2 Output table of experiments
  output$exp <- renderTable({
    experiments()
  }, rownames = TRUE)


  # 3.3 Output table of PIs
  output$PI <- renderTable({
    temp <- table(experiments()[["PI"]]) %>%
              as.data.frame(stringsAsFactors = FALSE)
    colnames(temp) <- c("PI", "Number of acquisitions")
    assign("PI_exp", temp, envir = .GlobalEnv)
    return(PI_exp)
  }, rownames = TRUE)


  # 3.4 Output plot of scans over time
  output$time <- renderPlot({
    use_time <- experiments() %>%
                mutate(Date = as.Date(Date)) %>%
                mutate(YearMonth = format(Date, format = "%Y-%m")) %>%
                group_by(YearMonth) %>%
                summarise(Sum = n())
    ggplot(use_time, aes(x = YearMonth, y = Sum)) +
      geom_col() +
      labs(y = "Number of experiments", x = " Year - month") +
      theme_classic()
  })


  # 3.5 Define what happens when clicking on the download buttons
  # 3.5.1. Experiments to ODS
  output$downloadExpODS <- downloadHandler(

    # Create file name for file to be downloaded
    filename = function() {
      paste0("IMPALA-usage_experiments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".ods")
    },

    # Define content
    content = function(file){
      readODS::write_ods(experiments(), file)
    }
  )

  # 3.5.2. PIs to ODS
  output$downloadPIODS <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_PIs_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".ods")
    },
    content = function(file){
      readODS::write_ods(PI_exp, file)
    }
  )

  # 3.5.3. Experiments to XLSX
  output$downloadExpXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_experiments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(experiments(), file)
    }
  )

  # 3.5.4. PIs to XLSX
  output$downloadPIXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_PIs_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(PI_exp, file)
    }
  )

  # 3.5.5. Graph PDF
  output$downloadTimePDF <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Time_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".pdf")
    },
    content = function(file){
      ggsave(file, device = "pdf", width = 190, units = "mm")
    }
  )

  # 3.5.6. Graph PNG
  output$downloadTimePNG <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Time_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".png")
    },
    content = function(file){
      ggsave(file, device = "png", width = 190, units = "mm")
    }
  )

}


###############################################################################################################


##########################
# 4. Run the application #
##########################

# Run the application
shinyApp(ui = ui, server = server)

# END OF CODE #
