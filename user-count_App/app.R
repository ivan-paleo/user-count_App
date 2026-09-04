# Shiny app to summarize usage data at the IMPALA
# Process JSON exports from eLabFTW
# Written by Ivan Calandra

###############################################################################################################


#####################
# 1. Load libraries #
#####################

library(ggplot2)
library(readODS)
library(rjson)
library(shiny)
library(tidyverse)
library(writexl)


###############################################################################################################


###############################
# 2. Increase file size limit #
###############################

options(shiny.maxRequestSize = 10*1024^2)  # 10 MB limit


###############################################################################################################


################
# 3. Define UI #
################

ui <- fluidPage(

  # 3.0. Define custom style for tables that contain a summary line at the end
  # bold and thick separating line
  # The style is called 'summary-last-line'
  tags$style(HTML("
    /* Target the table inside the container */
    #summary-last-line table {
      border-collapse: collapse;
    }
    #summary-last-line table tbody tr:last-child {
      font-weight: bold;
      border-top: 3px solid #333;
    }
  ")),


  # 3.1. Application title
  titlePanel("Usage statistics at the Imaging Platform At LEIZA (IMPALA)"),

  sidebarLayout(

    # 3.2. Sidebar
    sidebarPanel(

      # upload JSON file
      fileInput("JSONfile", "Choose JSON File (exported from eLabFTW)",
                multiple = FALSE, accept = ".json"),

      # Separator line
      hr(style = "border-top: 1px solid #000000;"),

      # LEIZA logo
      img(src = "Leiza_Logo_Deskriptor_CMYK_rot_LEIZA.png", height = 150),

      # Separator line
      hr(style = "border-top: 1px solid #000000;"),

      # GitHub
      splitLayout(cellWidths = c("40%", "60%"),
                  actionButton("GitHub", "user-count_App",
                               icon = icon("github", lib = "font-awesome"),
                               onclick = "window.open('https://github.com/ivan-paleo/user-count_App', '_blank')"),
                  h5(HTML("&#129152; Infos and help"))
      ),


      # Version number / date - ADJUST WITH NEW VERSION / DATE
      # Credits
      splitLayout(cellWidths = c("50%", "50%"),
                  h5("v1.2 (2026-09-04)"),
                  h5("By Ivan Calandra")
      ),

      # Width of the sidebar (default = 2)
      width = 3
    ),

    # 3.3. Main panel
    mainPanel(

      # Tabs
      tabsetPanel(type = "tabs",

        # Tabs, their UIs will be rendered in the server call below
        tabPanel("All experiments", fluidRow(
          h2("All experiments sorted by year and PI"),
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

        tabPanel("Instrument", fluidRow(
          h2("Number of experiments per instrument"),

          # Apply the style 'summary-last-line'
          tags$div(id = "summary-last-line", tableOutput("instr")),
          downloadButton("downloadInstrXLSX", "Download to XLSX"),
          downloadButton("downloadInstrODS", "Download to ODS")
        )),

        tabPanel("Experiments over time", fluidRow(
          h2("Number of experiments over time"),
          actionButton("month", "Per Month"),
          actionButton("year", "Per Year"),
          hr(),
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
# 4. Define server logic #
##########################

server <- function(input, output) {

  # 4.1 Read and format data
  # Use reactive() to use input file
  experiments <- reactive({

    # Ensure that file has been uploaded before proceeding
    req(input$JSONfile)

    # Read uploaded JSON file
    experiments <- fromJSON(file = input$JSONfile$datapath)

    # Extract PI names and dates of scans
    PI <- sapply(experiments, FUN = function(x) {
          # Get the extra_fields list
          extra_fields <- x[["metadata_decoded"]][["extra_fields"]]

          # Try to extract PI value, trying multiple possible keys
          pi_value <- if ("PI" %in% names(extra_fields)) {
                        extra_fields[["PI"]][["value"]]
                      } else {
                        if ("PI (component name)" %in% names(extra_fields)) {
                          extra_fields[["PI (component name)"]][["value"]]
                        } else {
                          NA
                        }
                      }
          return(pi_value)
          })

    Scan_date <- sapply(experiments, FUN = function(x) c(x[["date"]]))
    Scan_year <- format(as.Date(Scan_date), "%Y")
    equip <- sapply(experiments, FUN = function(x) c(x[["items_links"]][[1]][["title"]]))
    table_users <- data.frame(PI = PI, Date = Scan_date, Year = Scan_year, Instrument = equip)  %>%
                   arrange(Year, PI)
    return(table_users)
  })


  # 4.2 Output table of experiments
  output$exp <- renderTable({
    experiments()
  }, rownames = TRUE)


  # 4.3 Output table of PIs
  output$PI <- renderTable({
    use_PI <- table(experiments()[["PI"]]) %>%
              as.data.frame(stringsAsFactors = FALSE)
    colnames(use_PI) <- c("PI", "Number of acquisitions")
    assign("PI_exp", use_PI, envir = .GlobalEnv)
    return(PI_exp)
  }, rownames = TRUE)


  # 4.4 Output table of instruments
  output$instr <- renderTable({
    use_instr <- experiments() %>%
      group_by(Instrument) %>%
      summarise(Sum = n())
    colnames(use_instr) <- c("Instrument", "Number of acquisitions")
    use_instr <- rbind(use_instr, c("Total", sum(use_instr[["Number of acquisitions"]])))
    assign("Instr_exp", use_instr, envir = .GlobalEnv)
    return(Instr_exp)
  })


  # 4.5 Output plot of scans over time
  v <- reactiveValues(data = NULL)

  observeEvent(input$month, {
    v$data <- experiments() %>%
              mutate(Date = as.Date(Date)) %>%
              mutate(x_axis = format(Date, format = "%Y-%m")) %>%
              group_by(x_axis) %>%
              summarise(Sum = n())
  })

  observeEvent(input$year, {
    v$data <- experiments() %>%
              mutate(x_axis = Year) %>%
              group_by(x_axis) %>%
              summarise(Sum = n())
  })

  output$time <- renderPlot({
    ggplot(v$data, aes(x = x_axis, y = Sum)) +
      geom_col() +
      labs(y = "Number of experiments", x = NULL) +
      theme_classic() +
      theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1))
  })


  # 4.6 Define what happens when clicking on the download buttons
  # 4.6.1. Experiments to ODS
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

  # 4.6.2. Experiments to XLSX
  output$downloadExpXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_experiments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(experiments(), file)
    }
  )

  # 4.6.3. PIs to ODS
  output$downloadPIODS <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_PIs_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".ods")
    },
    content = function(file){
      readODS::write_ods(PI_exp, file)
    }
  )

  # 4.6.4. PIs to XLSX
  output$downloadPIXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_PIs_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(PI_exp, file)
    }
  )

  # 4.6.5. Instruments to ODS
  output$downloadInstrODS <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Instruments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".ods")
    },
    content = function(file){
      readODS::write_ods(Instr_exp, file)
    }
  )

  # 4.6.6. Instruments to XLSX
  output$downloadInstrXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Instruments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(Instr_exp, file)
    }
  )

  # 4.6.7. Graph PDF
  output$downloadTimePDF <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Time_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".pdf")
    },
    content = function(file){
      ggsave(file, device = "pdf", width = 240, height = 100, units = "mm")
    }
  )

  # 4.6.8. Graph PNG
  output$downloadTimePNG <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Time_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".png")
    },
    content = function(file){
      ggsave(file, device = "png", width = 240, height = 100, units = "mm")
    }
  )

}


###############################################################################################################


##########################
# 5. Run the application #
##########################

# Run the application
shinyApp(ui = ui, server = server)

# END OF CODE #
