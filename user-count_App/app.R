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
library(shinyWidgets)
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
    /* Right-align numeric columns by position (e.g., 2nd and 3rd columns) */
    #summary-last-line table td:nth-child(2),
    #summary-last-line table th:nth-child(2) {
    text-align: right;
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
                  h5("v1.3.1 (2026-09-07)"),
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

          # Check box to select instrument(s)
          # Will be defined in the server in order to extract values from the input file
          uiOutput("checkbox_instrPI"),

          # Check box to select type(s) of acquisition
          # Will be defined in the server in order to extract values from the input file
          uiOutput("checkbox_ServPI"),

          # Apply the style 'summary-last-line'
          tags$div(id = "summary-last-line", tableOutput("PI")),
          downloadButton("downloadPIXLSX", "Download to XLSX"),
          downloadButton("downloadPIODS", "Download to ODS")
        )),

        tabPanel("Instrument", fluidRow(
          h2("Number of experiments per instrument"),

          # Check box to select type(s) of acquisition
          # Will be defined in the server in order to extract values from the input file
          uiOutput("checkbox_ServInstr"),

          # Apply the style 'summary-last-line'
          tags$div(id = "summary-last-line", tableOutput("instr")),
          downloadButton("downloadInstrXLSX", "Download to XLSX"),
          downloadButton("downloadInstrODS", "Download to ODS")
        )),

        tabPanel("Type", fluidRow(
          h2("Number of experiments per type"),

          # Check box to select instrument(s)
          # Will be defined in the server in order to extract values from the input file
          uiOutput("checkbox_instrServ"),

          # Apply the style 'summary-last-line'
          tags$div(id = "summary-last-line", tableOutput("serv")),
          downloadButton("downloadServXLSX", "Download to XLSX"),
          downloadButton("downloadServODS", "Download to ODS")
        )),

        tabPanel("Experiments over time", fluidRow(
          h2("Number of experiments over time"),

          # Check box to select instrument(s)
          # Will be defined in the server in order to extract values from the input file
          uiOutput("checkbox_instrTime"),

          # Check box to select type(s) of acquisition
          # Will be defined in the server in order to extract values from the input file
          uiOutput("checkbox_ServTime"),

          # Radio buttons that look like action buttons
          radioGroupButtons(
            inputId = "time_group",
            label = "Time grouping",
            choices = c("Month-Year", "Year"),
            selected = "Month-Year"
          ),

          # Check box to show continuous x-axis or current values only
          checkboxInput("x_cont", "Continuous x-axis", value = FALSE),

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
    serv <- sapply(experiments, FUN = function(x) c(x[["metadata_decoded"]][["extra_fields"]][["Service"]][["value"]]))
    serv_reco <- ifelse(serv %in% c("Yes", "on"), "Service", "Collaboration")
    table_users <- data.frame(PI = PI, Date = Scan_date, Year = Scan_year, Type = serv_reco, Instrument = equip) %>%
                   arrange(Year, PI)
    return(table_users)
  })


  # 4.2 Output table of experiments
  output$exp <- renderTable({
    experiments()
  }, rownames = TRUE)


  # 4.3 Output table of PIs
  # 4.3.1 Select instruments
  output$checkbox_instrPI <- renderUI({

    # Get instruments from uploaded file
    instr_list <- unique(experiments()[["Instrument"]])

    # Create checkbox group with all instruments
    checkboxGroupInput("sel_instrPI", "Select instrument(s)",
                       choices = instr_list,
                       selected = instr_list) # Select all by default
  })

  # 4.3.2 Select types (see 4.3.1)
  output$checkbox_ServPI <- renderUI({
    serv_list <- unique(experiments()[["Type"]])
    checkboxGroupInput("sel_TypePI", "Select type(s)",
                       choices = serv_list,
                       selected = serv_list)
  })

  # 4.3.3 Filter instruments
  filtered_instrPI <- reactive({
    experiments() %>%
    filter(Instrument %in% input$sel_instrPI) %>%
    filter(Type %in% input$sel_TypePI)
  })

  # 4.3.4 Table of PIs
  output$PI <- renderTable({
    use_PI <- table(filtered_instrPI()[["PI"]]) %>%
              as.data.frame()
    total_row_PI <- data.frame(Var1 = "Total", Freq = sum(use_PI$Freq))
    use_PI <- rbind(use_PI, total_row_PI)
    colnames(use_PI) <- c("PI", "Number of acquisitions")
    assign("PI_exp", use_PI, envir = .GlobalEnv)
    return(PI_exp)
  })


  # 4.4 Output table of instruments
  # 4.4.1 Select type (see 4.3.1)
  output$checkbox_ServInstr <- renderUI({
      serv_list <- unique(experiments()[["Type"]])
      checkboxGroupInput("sel_TypeServ", "Select type(s)",
                         choices = serv_list,
                         selected = serv_list)
    })

  # 4.4.2 Filter instruments
  filtered_ServInstr <- reactive({
      experiments() %>% filter(Type %in% input$sel_TypeServ)
  })

  # 4.4.3 Table of instruments
  output$instr <- renderTable({
    use_instr <- filtered_ServInstr() %>%
      group_by(Instrument) %>%
      summarise(Sum = n())
    colnames(use_instr) <- c("Instrument", "Number of acquisitions")
    use_instr <- rbind(use_instr, c("Total", sum(use_instr[["Number of acquisitions"]])))
    assign("Instr_exp", use_instr, envir = .GlobalEnv)
    return(Instr_exp)
  })


  # 4.5 Output table of services
  # 4.5.1 Select instruments (see 4.3.1)
  output$checkbox_instrServ <- renderUI({
    instr_list <- unique(experiments()[["Instrument"]])
    checkboxGroupInput("sel_instrServ", "Select instrument(s)",
                       choices = instr_list,
                       selected = instr_list)
  })

  # 4.5.2 Filter instruments
  filtered_instrServ <- reactive({
    experiments() %>% filter(Instrument %in% input$sel_instrServ)
  })

  # 4.5.3 Table of services
  output$serv <- renderTable({
    use_serv <- filtered_instrServ() %>%
      group_by(Type) %>%
      summarise(`Number of acquisitions` = n())
    use_serv <- rbind(use_serv, c("Total", sum(use_serv[["Number of acquisitions"]])))
    assign("Serv_exp", use_serv, envir = .GlobalEnv)
    return(Serv_exp)
  })


  # 4.6 Output plot of scans over time
  # 4.6.1 Select instruments (see 4.3.1)
  output$checkbox_instrTime <- renderUI({
    instr_list <- unique(experiments()[["Instrument"]])
    checkboxGroupInput("sel_instrTime", "Select instrument(s)",
                       choices = instr_list,
                       selected = instr_list) # Select all by default
  })

  # 4.6.2 Select types (see 4.3.1)
  output$checkbox_ServTime <- renderUI({
    serv_list <- unique(experiments()[["Type"]])
    checkboxGroupInput("sel_TypeTime", "Select type(s)",
                       choices = serv_list,
                       selected = serv_list)
  })

  # 4.6.3 Filter instruments and types
  filtered_Time <- reactive({
    experiments() %>%
    filter(Instrument %in% input$sel_instrTime) %>%
    filter(Type %in% input$sel_TypeTime)
  })

  # 4.6.4 Group
  grouped_data <- reactive({
    if (input$time_group == "Month-Year") {

      # Extract month-year
      temp <- filtered_Time() %>%
              mutate(Date = as.Date(Date)) %>%
              mutate(x_axis = format(Date, format = "%Y-%m"))
    }
    if (input$time_group == "Year") {

      # Extract year
      temp <- filtered_Time() %>%
              mutate(x_axis = Year)
    }

    # Group by x_axis (month-year or year) and calculate sum by group
    temp <- temp %>%
            group_by(x_axis) %>%
            summarise(Sum = n())
    return(temp)
  })

  # 4.6.5 Continuous x-axis
  cont_data <- reactive({

    # If checkbox is ticked
    if (input$x_cont == TRUE) {

      # Create sequence from first to last date
      first_date <- min(grouped_data()$x_axis)
      last_date <- max(grouped_data()$x_axis)
      # For month-year dates
      if (input$time_group == "Month-Year") {
        all_dates <- seq.Date(from = as.Date(paste0(first_date, "-01")),
                              to = as.Date(paste0(last_date, "-01")),
                              by = "month") %>%
                     format("%Y-%m")
      }
      # For year dates
      if (input$time_group == "Year") {
        all_dates <- seq.Date(from = as.Date(paste0(first_date, "-01-01")),
                              to = as.Date(paste0(last_date, "-01-01")),
                              by = "year") %>%
          format("%Y")
      }

      # Adjust levels of x_axis
      temp <- grouped_data() %>%
              mutate(x_axis = factor(x_axis, levels = all_dates))
    } else {

      # If checkbox is not ticked, do nothing
      temp <- grouped_data()
    }
    return(temp)
  })

  # 4.6.6 Plot
  output$time <- renderPlot({
    ggplot(cont_data(), aes(x = x_axis, y = Sum)) +
      geom_col() +
      labs(y = "Number of acquisitions", x = NULL) +
      theme_classic() +
      theme(axis.text.x = element_text(angle = 45, vjust = 1, hjust = 1)) +

      # Round y-axis labels to integer
      scale_y_continuous(breaks = function(limits) round(pretty(limits))) +

      # Do not drop levels (necessary for continuous x-axis)
      scale_x_discrete(drop = FALSE)
  })


  # 4.7 Define what happens when clicking on the download buttons
  # 4.7.1 Experiments to ODS
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

  # 4.7.2 Experiments to XLSX
  output$downloadExpXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_experiments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(experiments(), file)
    }
  )

  # 4.7.3 PIs to ODS
  output$downloadPIODS <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_PIs_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".ods")
    },
    content = function(file){
      readODS::write_ods(PI_exp, file)
    }
  )

  # 4.7.4 PIs to XLSX
  output$downloadPIXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_PIs_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(PI_exp, file)
    }
  )

  # 4.7.5 Instruments to ODS
  output$downloadInstrODS <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Instruments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".ods")
    },
    content = function(file){
      readODS::write_ods(Instr_exp, file)
    }
  )

  # 4.7.6 Instruments to XLSX
  output$downloadInstrXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Instruments_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(Instr_exp, file)
    }
  )

  # 4.7.7 Services to ODS
  output$downloadServODS <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Services_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".ods")
    },
    content = function(file){
      readODS::write_ods(Serv_exp, file)
    }
  )

  # 4.7.8 Services to XLSX
  output$downloadServXLSX <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Services_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(Serv_exp, file)
    }
  )

  # 4.7.9 Graph PDF
  output$downloadTimePDF <- downloadHandler(
    filename = function() {
      paste0("IMPALA-usage_Time_", format(Sys.time(), "%Y-%m-%d_%H-%M-%S"), ".pdf")
    },
    content = function(file){
      ggsave(file, device = "pdf", width = 240, height = 100, units = "mm")
    }
  )

  # 4.7.10 Graph PNG
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
