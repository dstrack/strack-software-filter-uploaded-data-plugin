/*
Copyright 2017 Dirk Strack

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

------------------------------------------------------------------------------
Plugin for filtering uploaded data.
When you encounter errors in the attempt to process an uploaded file or pasted data,
and you have a large import file it can be difficult to find the bad rows that cause the error.
When a row has fewer columns than the count of columns found in the first row it is a bad row.
The filter process removes bad rows from the input and returns the bad rows with a row number in the bad rows item.
The bad rows can be optionally displayed on the "Data Validation" or "Upload Results" page.
You have to create a Page Item PXX_BAD_ROWS . The PXX_BAD_ROWS has to be set in the 'Bad Rows Item' attribute of the plugin.

If you get an "ORA-06502: PL/SQL: numeric or value error: character string buffer too small" error
when you try to process the uploaded data or only a small subset of the uploaded rows is processed
then use this plugin to filter the uploaded data.

- Plugin Callbacks:
- Execution Function Name: import_filter_plugin.Filter_Upload
	attribute_01 : Import From Item
	attribute_02 : Separator Item
	attribute_03 : File Name Item
	attribute_04 : Character Set Item
	attribute_05 : Bad Rows Item
	attribute_06 : Bad Rows Limit
	attribute_07 : Show Success Message

*/

CREATE OR REPLACE PACKAGE import_filter_plugin
IS
	TYPE cur_type IS REF CURSOR;
	g_msg_file_name_empty 	CONSTANT VARCHAR2(50) := 'File name is empty.';
	g_msg_file_empty 		CONSTANT VARCHAR2(50) := 'File content is empty.';
	g_msg_line_delimiter 	CONSTANT VARCHAR2(50) := 'Line delimiter not found.';
	g_msg_separator 		CONSTANT VARCHAR2(50) := 'Separator not found in first line.';
	g_msg_bad_row			CONSTANT VARCHAR2(50) := 'Row %0 : %1';
	g_msg_process_success 	CONSTANT VARCHAR2(100) := 'Filtered uploaded data. Found %0 good rows and %1 bad rows.';
	g_linemaxsize     		CONSTANT INTEGER 	  := 4000;

	FUNCTION Blob_to_Clob(
		p_blob IN BLOB,
		p_blob_charset IN VARCHAR2 DEFAULT NULL
	)  return CLOB;

	FUNCTION Split_Clob(
		p_clob IN CLOB,
		p_delimiter IN VARCHAR2
	) RETURN sys.odciVarchar2List PIPELINED;	-- VARCHAR2(4000)

	PROCEDURE Filter_Uploaded_Data (
		p_Import_From		IN OUT VARCHAR2, -- UPLOAD or PASTE
		p_Column_Delimiter  IN VARCHAR2,
		p_File_Name			IN VARCHAR2,
		p_File_Table_Name	IN VARCHAR2,
		p_Character_Set		IN VARCHAR2,
		p_Bad_Rows_Limit	IN OUT INTEGER,
		p_Good_Rows_Cnt		OUT INTEGER,
		p_Return_Bad_Rows 	OUT CLOB,
		p_Message			OUT VARCHAR2
	);

	FUNCTION Filter_Upload (
		p_process in apex_plugin.t_process,
		p_plugin  in apex_plugin.t_plugin )
	RETURN apex_plugin.t_process_exec_result;

END import_filter_plugin;
/
show errors


CREATE OR REPLACE PACKAGE BODY import_filter_plugin IS
	FUNCTION Blob_to_Clob(
		p_blob IN BLOB,
		p_blob_charset IN VARCHAR2 DEFAULT NULL
	)  return CLOB
	is
	  v_clob	NCLOB;
	  v_dstoff	PLS_INTEGER := 1;
	  v_srcoff	PLS_INTEGER := 1;
	  v_langctx PLS_INTEGER := 0;
	  v_warning PLS_INTEGER := 1;
	  v_blob_csid PLS_INTEGER;
	begin
		v_blob_csid := nvl(nls_charset_id(p_blob_charset), nls_charset_id('AL32UTF8'));

		if dbms_lob.getlength(p_blob) > 0 then
			dbms_lob.createtemporary(v_clob, true, dbms_lob.call);
			dbms_lob.converttoclob(
				dest_lob   =>	v_clob,
				src_blob   =>	p_blob,
				amount	   =>	dbms_lob.lobmaxsize,
				dest_offset =>	v_dstoff,
				src_offset	=>	v_srcoff,
				blob_csid	=>	v_blob_csid,
				lang_context => v_langctx,
				warning		 => v_warning
			);
		end if;
		return v_clob;
	end Blob_to_Clob;

	FUNCTION Split_Clob(
		p_clob IN CLOB,
		p_delimiter IN VARCHAR2
	) RETURN sys.odciVarchar2List PIPELINED	-- VARCHAR2(4000)
	IS
		v_dellen    CONSTANT INTEGER := length(p_delimiter);
		v_pos2 		INTEGER			:= dbms_lob.getlength(p_clob);
		v_pos  		INTEGER			:= 1;
		v_linelen	INTEGER;
	begin
		if p_clob IS NOT NULL then
			loop
				exit when v_pos2 = 0;
				v_pos2 := dbms_lob.instr( p_clob, p_delimiter, v_pos );
				v_linelen := case when v_pos2 >= v_pos
					then least(v_pos2 - v_pos, g_linemaxsize)
					else g_linemaxsize end;
				pipe row( dbms_lob.substr( p_clob, v_linelen, v_pos ) );
				v_pos := v_pos2 + v_dellen;
			end loop;
		end if;
		return ;
	END;

	FUNCTION Decode_Delimiter(
		p_delimiter IN VARCHAR2
	)
	RETURN VARCHAR2 DETERMINISTIC
	IS
	BEGIN
		return case p_delimiter
			when '\t' then chr(9)	-- tab
			when '\n' then chr(10)	-- lf
			when '\r' then chr(13)	-- cr
			else p_delimiter
		end;
	END Decode_Delimiter;

	PROCEDURE Filter_Uploaded_Data (
		p_Import_From		IN OUT VARCHAR2, -- UPLOAD or PASTE. UPLOAD will be replaced by PASTE
		p_Column_Delimiter  IN VARCHAR2,
		p_File_Name			IN VARCHAR2,
		p_File_Table_Name	IN VARCHAR2,
		p_Character_Set		IN VARCHAR2,
		p_Bad_Rows_Limit	IN OUT INTEGER,
		p_Good_Rows_Cnt		OUT INTEGER,
		p_Return_Bad_Rows 	OUT CLOB,
		p_Message			OUT VARCHAR2
	)
	is
		v_Clob   			CLOB;
		v_Bad_Result 		CLOB;
		v_Good_Result 		CLOB;
		v_Line_Delimiter 	VARCHAR2(10);
		v_Column_Delimiter 	VARCHAR2(10);
		v_Row_Line 			VARCHAR2(32767);
		v_Bad_Rows_Limit	PLS_INTEGER := NVL(p_Bad_Rows_Limit, 100);
		v_Bad_Rows_Cnt 		PLS_INTEGER := 0;
		v_Good_Rows_Cnt 	PLS_INTEGER := 0;
		v_Column_Cnt 		NUMBER;
		v_Offset	 		NUMBER;
   		cv 					CUR_TYPE;
	begin
		p_Bad_Rows_Limit	:= 0;
		p_Good_Rows_Cnt		:= 0;
		dbms_lob.createtemporary(v_Clob, true, dbms_lob.call);
		dbms_lob.createtemporary(v_Bad_Result, true, dbms_lob.call);
		dbms_lob.createtemporary(v_Good_Result, true, dbms_lob.call);

		v_Column_Delimiter := Decode_Delimiter(p_Column_Delimiter);

		if p_Import_From = 'UPLOAD' then
			if p_File_Name IS NULL then
				p_Message := g_msg_file_name_empty;
				return;
			end if;

			-- load file content into v_Clob from WWV_FLOW_FILES or APEX_APPLICATION_TEMP_FILES
			OPEN cv FOR 'SELECT import_filter_plugin.Blob_to_Clob(T.Blob_Content, :a)'
					|| ' FROM ' || DBMS_ASSERT.ENQUOTE_NAME(p_File_Table_Name)
					|| ' T WHERE T.Name = :b'
					USING p_Character_Set, p_File_Name;
			FETCH cv INTO v_Clob;
			IF cv%NOTFOUND THEN
				p_Message := g_msg_file_empty;
				return;
			END IF;
			CLOSE cv;
		elsif p_Import_From = 'PASTE' then
			-- load file content into v_Clob from APEX_COLLECTIONS
			SELECT clob001
			INTO v_Clob
			FROM apex_collections
			WHERE collection_name = 'CLOB_CONTENT';
		end if;
		-- try line delimiter \r\n -- crlf
		v_Line_Delimiter := Decode_Delimiter('\r') || Decode_Delimiter('\n');
		v_Offset   := dbms_lob.instr(v_Clob, v_Line_Delimiter);
		if v_Offset = 0 or v_Offset >= g_linemaxsize then
			-- try line delimiter \n
			v_Line_Delimiter := Decode_Delimiter('\n');
			v_Offset   := dbms_lob.instr(v_Clob, v_Line_Delimiter);
		end if;
		if v_Offset = 0 or v_Offset >= g_linemaxsize then
			-- try line delimiter \r
			v_Line_Delimiter := Decode_Delimiter('\r');
			v_Offset   := dbms_lob.instr(v_Clob, v_Line_Delimiter);
		end if;
		if v_Offset = 0 or v_Offset >= g_linemaxsize  then
			p_Message := g_msg_line_delimiter;
			return;
		end if;

		v_Row_Line := SUBSTR(v_Clob, 1, v_Offset - 1);
		v_Column_Cnt := LENGTH(v_Row_Line) - LENGTH(REPLACE(v_Row_Line, v_Column_Delimiter));
		if v_Column_Cnt = 0 then
			p_Message := g_msg_separator;
			return;
		end if;

		for c_rows in (
			SELECT S.Column_Value, ROWNUM Line_No
			FROM TABLE( import_filter_plugin.Split_Clob(v_Clob, v_Line_Delimiter) ) S
		)
		loop
			if c_rows.Column_Value IS NOT NULL then
				v_Row_Line := c_rows.Column_Value || v_Line_Delimiter;
				-- check count of columns
				if instr(v_Row_Line, v_Column_Delimiter, 1, v_Column_Cnt) = 0 then
					v_Bad_Rows_Cnt := v_Bad_Rows_Cnt + 1;
					if v_Bad_Rows_Cnt <= v_Bad_Rows_Limit then
						v_Row_Line := APEX_LANG.LANG (
							p_primary_text_string => g_msg_bad_row,
							p0 => c_rows.Line_No,
							p1 => v_Row_Line,
							p_primary_language => 'en'
						);
						dbms_lob.writeappend(v_Bad_Result, length(v_Row_Line), v_Row_Line);
					end if;
				else
					v_Good_Rows_Cnt := v_Good_Rows_Cnt + 1;
					dbms_lob.writeappend(v_Good_Result, length(v_Row_Line), v_Row_Line);
				end if;
			end if;
		end loop;
		if p_Import_From = 'PASTE' then
			APEX_COLLECTION.UPDATE_MEMBER (
				p_collection_name => 'CLOB_CONTENT',
				p_seq => '1',
				p_clob001 => v_Good_Result
			);
		elsif p_Import_From = 'UPLOAD' then
			apex_collection.truncate_collection('CLOB_CONTENT');
			apex_collection.add_member (
				p_collection_name => 'CLOB_CONTENT',
				p_clob001 => v_Good_Result
			);
			p_Import_From := 'PASTE';
		end if;
		p_Return_Bad_Rows  	:= v_Bad_Result;
		p_Bad_Rows_Limit	:= v_Bad_Rows_Cnt;
		p_Good_Rows_Cnt		:= v_Good_Rows_Cnt;
		p_Message 			:= 'OK';
	end Filter_Uploaded_Data;

	FUNCTION Filter_Upload (
		p_process in apex_plugin.t_process,
		p_plugin  in apex_plugin.t_plugin )
	RETURN apex_plugin.t_process_exec_result
	IS
		v_exec_result apex_plugin.t_process_exec_result;
		v_Import_From		VARCHAR2(50);
		v_Import_From_Item	VARCHAR2(50);
		v_Column_Delimiter	VARCHAR2(50);
		v_File_Name			VARCHAR2(1000);
		v_File_Name_Item	VARCHAR2(50);
		v_File_Table_Name	APEX_APPLICATION_PAGE_ITEMS.ATTRIBUTE_01%TYPE;
		v_Character_Set		VARCHAR2(200);
		v_Bad_Rows_Item		VARCHAR2(50);
		v_Return_Bad_Rows 	CLOB;
		v_Bad_Rows_Cnt	INTEGER;
		v_Good_Rows_Cnt		INTEGER;
		v_Show_Message		VARCHAR2(10);
		v_Message			VARCHAR2(200);
	BEGIN
		dbms_lob.createtemporary(v_Return_Bad_Rows, true, dbms_lob.call);
		if apex_application.g_debug then
			apex_plugin_util.debug_process (
				p_plugin => p_plugin,
				p_process => p_process
			);
		end if;
		v_Import_From_Item := p_process.attribute_01;
		v_Import_From     := APEX_UTIL.GET_SESSION_STATE(v_Import_From_Item);
		v_Column_Delimiter:= APEX_UTIL.GET_SESSION_STATE(p_process.attribute_02);
		v_File_Name_Item  := p_process.attribute_03;
		v_File_Name       := APEX_UTIL.GET_SESSION_STATE(v_File_Name_Item);
		v_Character_Set   := APEX_UTIL.GET_SESSION_STATE(p_process.attribute_04);
		v_Bad_Rows_Item   := p_process.attribute_05;
		v_Bad_Rows_Cnt  := nvl(to_number(p_process.attribute_06), 1000000);
		v_Show_Message    := p_process.attribute_07;

		if v_File_Name_Item IS NOT NULL then
			-- determinate file source : WWV_FLOW_FILES or APEX_APPLICATION_TEMP_FILES
			SELECT ATTRIBUTE_01
			INTO v_File_Table_Name
			FROM APEX_APPLICATION_PAGE_ITEMS
			WHERE APPLICATION_ID 	= apex_application.g_flow_id
			AND PAGE_ID 			= apex_application.g_flow_step_id
			AND ITEM_NAME 			= v_File_Name_Item;
		end if;
		if apex_application.g_debug then
			apex_debug.info('Import_From_Item: %s', v_Import_From_Item);
			apex_debug.info('Import_From     : %s', v_Import_From);
			apex_debug.info('Column_Delimiter: %s', v_Column_Delimiter);
			apex_debug.info('File_Name_Item  : %s', v_File_Name_Item);
			apex_debug.info('File_Name       : %s', v_File_Name);
			apex_debug.info('File_Table_Name : %s', v_File_Table_Name);
			apex_debug.info('Character_Set   : %s', v_Character_Set);
			apex_debug.info('Bad_Rows_Item   : %s', v_Bad_Rows_Item);
			apex_debug.info('Bad_Rows_Limit  : %s', v_Bad_Rows_Cnt);
		end if;

		import_filter_plugin.Filter_Uploaded_Data (
			p_Import_From 		=> v_Import_From,
			p_Column_Delimiter 	=> v_Column_Delimiter,
			p_File_Name 		=> v_File_Name,
			p_File_Table_Name 	=> v_File_Table_Name,
			p_Character_Set 	=> v_Character_Set,
			p_Bad_Rows_Limit 	=> v_Bad_Rows_Cnt,
			p_Good_Rows_Cnt 	=> v_Good_Rows_Cnt,
			p_Return_Bad_Rows 	=> v_Return_Bad_Rows,
			p_Message			=> v_Message
		);
		apex_util.set_session_state(v_Import_From_Item, v_Import_From);
		if v_Bad_Rows_Item IS NOT NULL then
			apex_util.set_session_state(v_Bad_Rows_Item, v_Return_Bad_Rows);
		end if;
		if apex_application.g_debug then
			apex_debug.info('Bad_Rows_Count  : %s', v_Bad_Rows_Cnt);
			apex_debug.info('Good_Rows_Count : %s', v_Good_Rows_Cnt);
			apex_debug.info('Error Message   : %s', v_Message);
		end if;
		v_exec_result.execution_skipped := (v_Message != 'OK');
		if v_Show_Message = 'Y' then
			if v_Message = 'OK' then
				v_exec_result.success_message := APEX_LANG.LANG (
					p_primary_text_string => g_msg_process_success,
					p0 => v_Good_Rows_Cnt,
					p1 => v_Bad_Rows_Cnt,
					p_primary_language => 'en'
				);
			else
				v_exec_result.success_message := APEX_LANG.LANG (
					p_primary_text_string => v_Message,
					p_primary_language => 'en'
				);
			end if;
		end if;
		RETURN v_exec_result;
	END Filter_Upload;
END import_filter_plugin;
/
show errors

