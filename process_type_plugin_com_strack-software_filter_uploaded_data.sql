set define off verify off feedback off
whenever sqlerror exit sql.sqlcode rollback
--------------------------------------------------------------------------------
--
-- ORACLE Application Express (APEX) export file
--
-- You should run the script connected to SQL*Plus as the Oracle user
-- APEX_050000 or as the owner (parsing schema) of the application.
--
-- NOTE: Calls to apex_application_install override the defaults below.
--
--------------------------------------------------------------------------------
begin
wwv_flow_api.import_begin (
 p_version_yyyy_mm_dd=>'2013.01.01'
,p_release=>'5.0.3.00.03'
,p_default_workspace_id=>5650392499697142
,p_default_application_id=>2000
,p_default_owner=>'DVLA_GHANA_DEV'
);
end;
/
prompt --application/ui_types
begin
null;
end;
/
prompt --application/shared_components/plugins/process_type/com_strack_software_filter_uploaded_data
begin
wwv_flow_api.create_plugin(
 p_id=>wwv_flow_api.id(20232747927132556)
,p_plugin_type=>'PROCESS TYPE'
,p_name=>'COM.STRACK-SOFTWARE.FILTER_UPLOADED_DATA'
,p_display_name=>'Filter Uploaded Data'
,p_supported_ui_types=>'DESKTOP:JQM_SMARTPHONE'
,p_execution_function=>'import_filter_plugin.Filter_Upload'
,p_substitute_attributes=>true
,p_subscribe_plugin_settings=>true
,p_help_text=>wwv_flow_utilities.join(wwv_flow_t_varchar2(
'Plugin for filtering uploaded data. ',
'When you encounter errors in the attempt to process an uploaded file or pasted data,',
'and you have a large import file it can be difficult to find the bad rows that cause the error.',
'When a row has fewer columns than the count of columns found in the first row it is a bad row.',
'The filter process removes bad rows from the input and returns the bad rows with a row number in the bad rows item.',
'The bad rows can be optionally displayed on the "Data Validation" or "Upload Results" page.',
'You have to create a Page Item PXX_BAD_ROWS . The PXX_BAD_ROWS has to be set in the ''Bad Rows Item'' attribute of the plugin.'))
,p_version_identifier=>'1.0'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(20250259043547743)
,p_plugin_id=>wwv_flow_api.id(20232747927132556)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>1
,p_display_sequence=>10
,p_prompt=>'Import From Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
,p_examples=>'PXX_IMPORT_FROM'
,p_help_text=>'Enter the page item to hold the Import From option chosen by the end user. You can type in the name or pick from the list of available items.'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(20260220550826387)
,p_plugin_id=>wwv_flow_api.id(20232747927132556)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>2
,p_display_sequence=>20
,p_prompt=>'Separator Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
,p_examples=>'PXX_SEPARATOR'
,p_help_text=>'Enter the page item to hold the Seperator text entered by the end user. You can type in the name or pick from the list of available items.'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(20260590216831321)
,p_plugin_id=>wwv_flow_api.id(20232747927132556)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>3
,p_display_sequence=>30
,p_prompt=>'File Name Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>true
,p_is_translatable=>false
,p_examples=>'PXX_FILE_NAME'
,p_help_text=>'Enter the page item to hold the File Name value entered by the end user. You can type in the name or pick from the list of available items.'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(20260834580838735)
,p_plugin_id=>wwv_flow_api.id(20232747927132556)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>4
,p_display_sequence=>40
,p_prompt=>'Character Set Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_examples=>'PXX_CHAR_SET'
,p_help_text=>'Enter the page item to hold the File Character Set selected by the end user. You can type in the name or pick from the list of available items.'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(20261166225871533)
,p_plugin_id=>wwv_flow_api.id(20232747927132556)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>5
,p_display_sequence=>50
,p_prompt=>'Bad Rows Item'
,p_attribute_type=>'PAGE ITEM'
,p_is_required=>false
,p_is_translatable=>false
,p_examples=>'PXX_BAD_ROWS'
,p_help_text=>wwv_flow_utilities.join(wwv_flow_t_varchar2(
'Enter the page item to hold the bad rows. You can type in the name or pick from the list of available items.',
'When the Plugin is processed, rows that do not contain the proper formating will be removed from the input data and will by added to the bad rows item.',
'To display the bad rows that where filtered from the input data,',
'Navigate to the page "XX - Data Validation" or "XX - Data Load Results" that was generated by the Data Load wizard. ',
'Create a region of type ''Static Content'' named "Bad Input Rows". For Conditional Display set Condition type to ''item /column not null'' and ''Expression 1'' to PXX_BAD_ROWS.',
'Create a page item PXX_BAD_ROWS of type ''Display Only'' in the Region "Bad Input Rows". Set "Template" to ''Hidden'' and "Label Column Span" to 0',
'Navigate back to the "XX  - Data Load Source" and assign the PXX_BAD_ROWS item name to "Bad Rows Item".'))
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(20380673416075272)
,p_plugin_id=>wwv_flow_api.id(20232747927132556)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>6
,p_display_sequence=>60
,p_prompt=>'Bad Rows Limit'
,p_attribute_type=>'NUMBER'
,p_is_required=>false
,p_default_value=>'200'
,p_display_length=>10
,p_max_length=>10
,p_unit=>'rows'
,p_is_translatable=>false
,p_help_text=>'Defines the maximum number of rows to be returned into the bad rows Item.'
);
wwv_flow_api.create_plugin_attribute(
 p_id=>wwv_flow_api.id(20680295717781513)
,p_plugin_id=>wwv_flow_api.id(20232747927132556)
,p_attribute_scope=>'COMPONENT'
,p_attribute_sequence=>7
,p_display_sequence=>70
,p_prompt=>'Show Success Message'
,p_attribute_type=>'CHECKBOX'
,p_is_required=>false
,p_default_value=>'Y'
,p_is_translatable=>false
,p_help_text=>wwv_flow_utilities.join(wwv_flow_t_varchar2(
'Set this attribute to ''Yes'' when a Success Message should be displayed.',
'The Message is of the form "Filtered uploaded data. Found %0 good rows and %1 bad rows." and is displayed, when a page branch with the option ''include process success message '' is followed.'))
);
end;
/
begin
wwv_flow_api.import_end(p_auto_install_sup_obj => nvl(wwv_flow_application_install.get_auto_install_sup_obj, false), p_is_component_import => true);
commit;
end;
/
set verify on feedback on define on
prompt  ...done
