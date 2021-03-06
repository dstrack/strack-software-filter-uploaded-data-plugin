# README:

Plugin for filtering uploaded data.

If you get an "ORA-06502: PL/SQL: numeric or value error: character string buffer too small" error
when you try to process the uploaded data or only a small subset of the uploaded rows is processed
then use this plugin to filter the uploaded data.

If you encounter errors in the attempt to process an uploaded file or pasted data,
and you have a large import file it can be difficult to find the bad rows that cause the error.
In this case you can use this plugin, to extract the bad formated rows with a row number into a page item.

When a row has fewer columns than the count of columns found in the first row, it is a bad row.
The filter process removes bad rows from the input and returns the bad rows with a row number in the bad rows item.
The bad rows can be optionally displayed on the "Data Validation" or "Upload Results" page.
You have to create a Page Item PXX_BAD_ROWS . The PXX_BAD_ROWS has to be set in the 'Bad Rows Item' attribute of the plugin.

To use this plugin navigate to a "XX - Data Load Source" page in your application.
Create a Page process.
Choose 'Process type' "Plug-ins".
Select Plug-in "Filter Uploaded Data".
Set 'Name' to "Filter Uploaded Data".
Set 'Sequence' to 5 to ensure that the process is executed before the "Parse Uploaded Data" process.
Set 'Point' to "On Submit - After Computations and Validations"
At 'Process Condition' set 'When Button Pressed' to "NEXT".

Now edit the settings of the plugin instance.
Set the mandantory attributes 'Import From Item', 'Separator Item', 'File Name Item' and 'Character Set Item'
to the same values that are used in the "Parse Uploaded Data" process.

Set the optional attribute 'Bad Rows Limit'. Define the maximum number of rows to be returned into the bad rows Item.

Set the optional attribute 'Show Success Message'. Set this attribute to 'Yes' when a success message should be displayed.
The Message is of the form "Filtered uploaded data. Found %0 good rows and %1 bad rows." and is displayed,
when a page branch with the option 'include process success message ' is followed.

Set the optional attribute 'Bad Rows Item' Enter the page item to receive the bad rows.
You can type in the name or pick from the list of available items.
When the Plugin is processed, rows that do not contain the proper formating will be removed
from the input data and will by added to the bad rows item.

In order to display the bad rows that where filtered from the input data,
navigate to the page "XX - Data / Table Mapping" or "XX - Data Load Results" that was generated by the Data Load wizard.
Create a region of type 'Static Content' named "Bad Input Rows".
Set Sequence to 5 to ensure that the Region is shown on top of the page.
Set Condition Type to 'Value of Item / Column in Expression 1 Is NOT NULL' 
and set 'Expression 1' to PXX_BAD_ROWS.
Create a page item PXX_BAD_ROWS of type 'Display Only' in the Region "Bad Input Rows".
Set "Template" to 'Hidden' and "Label Column Span" to 0, so that all available screen space can bee used.
Navigate back to the "XX - Data Load Source" and assign the PXX_BAD_ROWS item name to "Bad Rows Item".

The process is skipped when not data can be processced and one of the following success messages is returned:
'File name is empty.', 'Line delimiter not found.', 'Separator not found in first line.'.
The messages can be translated via enties in the Dynamic Translations Lists

----------
## Installation 

The package IMPORT_FILTER_PLUGIN has to be installed in the application schema. 
execute the file filter_uploaded_data_plsql_code.sql to install the required database objects.
You can add the file to the installation script of you application.

