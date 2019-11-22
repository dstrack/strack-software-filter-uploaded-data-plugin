/*
Copyright 2019 Dirk Strack, Strack Software Development

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
AUTHID CURRENT_USER
IS
	TYPE cur_type IS REF CURSOR;
	g_msg_file_name_empty 	CONSTANT VARCHAR2(50) := 'File name is empty.';
	g_msg_file_empty 		CONSTANT VARCHAR2(50) := 'File content is empty.';
	g_msg_no_data_found		CONSTANT VARCHAR2(50) := 'No valid data found in import file.';
	g_msg_line_delimiter 	CONSTANT VARCHAR2(50) := 'Line delimiter not found.';
	g_msg_separator_head 	CONSTANT VARCHAR2(50) := 'Separator not found in first line.';
	g_msg_separator_body	CONSTANT VARCHAR2(50) := 'Separator not found in line ';
	g_msg_bad_row			CONSTANT VARCHAR2(50) := 'Row %0 : %1';
	g_msg_process_success 	CONSTANT VARCHAR2(100) := 'Filtered uploaded data. Found %0 good rows and %1 bad rows.';
	g_linemaxsize     		CONSTANT INTEGER 	  := 4000;

	FUNCTION Blob_to_Clob(
		p_blob IN BLOB,
		p_blob_charset IN VARCHAR2 DEFAULT NULL
	)  return CLOB;

	FUNCTION Split_Clob(
		p_clob IN CLOB,
		p_Enclosed_By 		IN VARCHAR2,
		p_delimiter IN VARCHAR2
	) RETURN sys.odciVarchar2List PIPELINED;	-- VARCHAR2(4000)

	PROCEDURE Filter_Uploaded_Data (
		p_Import_From		IN OUT VARCHAR2, -- UPLOAD or PASTE
		p_Column_Delimiter  IN VARCHAR2 DEFAULT NULL,
		p_Enclosed_By       IN VARCHAR2 DEFAULT '"',
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

	function Charset_Code (p_Charset_Name VARCHAR2) return varchar2
	is
	begin
		return case lower(p_Charset_Name)
			when 'iso-8859-6' then 'AR8ISO8859P6' -- 'Arabic ISO-8859-6'
			when 'windows-1256' then 'AR8MSWIN1256' -- 'Arabic Windows 1256'
			when 'big5' then 'ZHT16MSWIN950' -- 'Chinese Big5'
			when 'gbk' then 'ZHS16GBK' -- 'Chinese GBK'
			when 'iso-8859-5' then 'CL8ISO8859P5' -- 'Cyrilic ISO-8859-5'
			when 'koi8-r' then 'CL8KOI8R' -- 'Cyrilic KOI8-R'
			when 'koi8-u' then 'CL8KOI8U' -- 'Cyrilic KOI8-U'
			when 'windows-1251' then 'CL8MSWIN1251' -- 'Cyrilic Windows 1251'
			when 'iso-8859-2' then 'EE8ISO8859P2' -- 'Eastern European ISO-8859-2'
			when 'windows-1250' then 'EE8MSWIN1250' -- 'Eastern European Windows 1250'
			when 'iso-8859-7' then 'EL8ISO8859P7' -- 'Greek ISO-8859-7'
			when 'windows-1253' then 'EL8MSWIN1253' -- 'Greek Windows 1253'
			when 'iso-8859-8-i' then 'IW8ISO8859P8' -- 'Hebrew ISO-8859-8-i'
			when 'windows-1255' then 'IW8MSWIN1255' -- 'Hebrew Windows 1255'
			when 'euc-jp' then 'JA16EUC' -- 'Japanese EUC'
			when 'shift_jis' then 'JA16SJIS' -- 'Japanese Shift JIS'
			when 'euc-kr' then 'KO16MSWIN949' -- 'Korean EUC'
			when 'iso-8859-4' then 'NEE8ISO8859P4' -- 'Northern European ISO-8859-4'
			when 'windows-1257' then 'BLT8MSWIN1257' -- 'Northern European Windows 1257'
			when 'iso-8859-3' then 'SE8ISO8859P3' -- 'Southern European ISO-8859-3'
			when 'tis-620' then 'TH8TISASCII' -- 'Thai TIS-620'
			when 'iso-8859-9' then 'WE8ISO8859P9' -- 'Turkish ISO-8859-9'
			when 'windows-1254' then 'TR8MSWIN1254' -- 'Turkish Windows 1254'
			when 'utf-8' then 'AL32UTF8' -- 'Unicode UTF-8'
			when 'utf-16be' then 'AL16UTF16' -- 'Unicode UTF-16 Big Endian'
			when 'utf-16le' then 'AL16UTF16LE' -- 'Unicode UTF-16 Little Endian'
			when 'windows-1258' then 'VN8MSWIN1258' -- 'Vietnamese Windows 1258'
			when 'iso-8859-1' then 'WE8ISO8859P1' -- 'Western European ISO-8859-1'
			when 'iso-8859-15' then 'WE8ISO8859P15' -- 'Western European ISO-8859-15'
			when 'windows-1252' then 'WE8MSWIN1252' -- 'Western European Windows 1252'
			when 'euc-tw' then 'ZHT32EUC' -- 'Chinese EUC'
			when 'us-ascii' then 'US7ASCII' -- 'US-ASCII'
			else p_Charset_Name
		end;
	end;

	FUNCTION Blob_to_Clob(
		p_blob IN BLOB,
		p_blob_charset IN VARCHAR2 DEFAULT NULL
	)  return CLOB
	is
	v_clob	CLOB;
	v_dstoff	INTEGER := 1;
	v_srcoff	INTEGER := 1;
	v_langctx 	INTEGER := 0;
	v_warning 	INTEGER := 1;
	v_blob_csid NUMBER;
	v_utf8_bom  raw(10) := hextoraw('EFBBBF');
	v_utf16le_bom raw(10) := hextoraw('FFFE');
	v_file_head raw(10);
	begin
		if dbms_lob.getlength(p_blob) > 3 then
			if p_blob_charset IS NOT NULL then
				v_blob_csid := nls_charset_id(Charset_Code(p_blob_charset));
			end if;
			if v_blob_csid IS NULL then
				v_blob_csid := DBMS_LOB.DEFAULT_CSID;
			end if;

			v_file_head := dbms_lob.substr(p_blob, 3, 1);
			if UTL_RAW.COMPARE (v_utf8_bom, v_file_head) = 0 then
				v_srcoff := 4;
				v_blob_csid := nls_charset_id('AL32UTF8');
			else 
				v_file_head := dbms_lob.substr(p_blob, 2, 1);
				if UTL_RAW.COMPARE (v_utf16le_bom, v_file_head) = 0 then
					v_srcoff := 3;
					v_blob_csid := nls_charset_id('AL16UTF16LE');
				end if;
			end if;

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

	FUNCTION Split_Clob (
		p_clob 				IN CLOB,
		p_Enclosed_By 		IN VARCHAR2,
		p_delimiter 		IN VARCHAR2
	) RETURN sys.odciVarchar2List PIPELINED	-- VARCHAR2(4000)
	IS
		v_dellen    PLS_INTEGER;
		v_loblen	PLS_INTEGER			:= dbms_lob.getlength(p_clob);
		v_pos2 		PLS_INTEGER			:= 1;
		v_pos  		PLS_INTEGER			:= 1;
		v_parity1	PLS_INTEGER			:= 1;
		v_parity2	PLS_INTEGER			:= 1;
		v_linelen	PLS_INTEGER;
		v_delimiter VARCHAR2(10);
		v_Line 		VARCHAR2(32767);
		v_Row_Line 	VARCHAR2(32767);
	begin
		v_delimiter	:= p_delimiter;
		v_dellen	:= length(v_delimiter);
		if p_clob IS NOT NULL and v_loblen > 0 and v_dellen > 0 then
			loop
				exit when v_pos2 >= v_loblen;
				v_pos2 := dbms_lob.instr( p_clob, v_delimiter, v_pos );
				if v_pos2 = 0 then -- process last line
					v_pos2 := v_loblen;
					v_linelen := least(v_pos2 - v_pos + v_dellen, g_linemaxsize);
					v_Row_Line := dbms_lob.substr( p_clob, v_linelen, v_pos );
				else
					v_linelen := least(v_pos2 - v_pos, g_linemaxsize);
					if p_Enclosed_By IS NOT NULL then 
						v_Line := dbms_lob.substr( p_clob, v_linelen, v_pos );
						v_parity2 := mod(abs(length(replace(v_Line, p_Enclosed_By))-v_linelen), 2);
						v_parity1 := abs(v_parity2 - v_parity1);
						v_Row_Line := v_Row_Line || v_Line;
						v_linelen := length(v_Row_Line);
					else
						v_Row_Line := dbms_lob.substr( p_clob, v_linelen, v_pos );
					end if;
				end if;
				if v_linelen > 0 and v_parity1 = 1 then 
					pipe row( v_Row_Line );
					v_Row_Line := null;
				end if;
				v_pos := v_pos2 + v_dellen;
			end loop;
		end if;
		return ;
	END;

	FUNCTION Find_Column_Delimiter (
		p_clob 			IN CLOB,
		p_New_Line 		IN VARCHAR2
	) RETURN VARCHAR2
	is
		v_Row_Line 			VARCHAR2(32767);
		v_Row_Line2 		VARCHAR2(32767);
		v_Column_Cnt 		PLS_INTEGER;
		v_Column_Cnt2 		PLS_INTEGER;
		v_Offset	 		PLS_INTEGER;
		v_Offset2	 		PLS_INTEGER;
		v_Column_Delimiter 	VARCHAR2(10);
		v_Nllen PLS_INTEGER := LENGTH(p_New_Line);
	begin 
	
		for c_rows in (
			SELECT S.Column_Value, ROWNUM Line_No
			FROM TABLE( apex_string.split(p_str => chr(9)||':#:|:;:,', p_sep => ':') ) S
		)
		loop
			v_Column_Delimiter := c_rows.Column_Value;
			v_Offset   := dbms_lob.instr(p_Clob, p_New_Line);
			v_Row_Line := RTRIM(dbms_lob.substr(p_clob, v_Offset - 1, 1), v_Column_Delimiter);
			v_Column_Cnt := 1 + LENGTH(v_Row_Line) - LENGTH(REPLACE(v_Row_Line, v_Column_Delimiter));

			v_Offset2   := dbms_lob.instr(p_clob, p_New_Line, v_Offset+v_Nllen);
			v_Row_Line2 := RTRIM(dbms_lob.substr(p_clob, v_Offset2 - v_Offset - v_Nllen, v_Offset+v_Nllen), v_Column_Delimiter);
			if LENGTH(v_Row_Line2) > 0 then 
				v_Column_Cnt2 := 1 + LENGTH(v_Row_Line2) - LENGTH(REPLACE(v_Row_Line2, v_Column_Delimiter));
			else 
				v_Column_Cnt2 := v_Column_Cnt;
			end if;
			if apex_application.g_debug then
				apex_debug.info('Find_Column_Delimiter : %s', v_Column_Delimiter);
				apex_debug.info('v_Column_Cnt : %s. Import_Row_Line : #%s#', v_Column_Cnt, v_Row_Line);
				apex_debug.info('v_Column_Cnt2 : %s. Import_Row_Line2 : #%s#', v_Column_Cnt2, v_Row_Line2);
			end if;
			if v_Column_Cnt > 1 and v_Column_Cnt = v_Column_Cnt2 then 
				return v_Column_Delimiter;
			end if;
		end loop;
		
		return v_Column_Delimiter;
	end;
	
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
		p_Column_Delimiter  IN VARCHAR2 DEFAULT NULL,
		p_Enclosed_By       IN VARCHAR2 DEFAULT '"',
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
		v_Line_Array 		apex_t_varchar2;
		v_Bad_Result 		CLOB;
		v_Good_Result 		CLOB;
		v_New_Line 			VARCHAR2(10);
		v_Column_Delimiter 	VARCHAR2(10);
		v_Enclosed_By    	VARCHAR2(10);
		v_Row_Line 			VARCHAR2(32767);
		v_Bad_Rows_Limit	PLS_INTEGER := NVL(p_Bad_Rows_Limit, 100);
		v_Bad_Rows_Cnt 		PLS_INTEGER := 0;
		v_Good_Rows_Cnt 	PLS_INTEGER := 0;
		v_Column_Cnt 		PLS_INTEGER;
		v_Column_Limit		PLS_INTEGER;
		v_Offset	 		PLS_INTEGER;
   		cv 					CUR_TYPE;
	begin
		p_Bad_Rows_Limit	:= 0;
		p_Good_Rows_Cnt		:= 0;
		dbms_lob.createtemporary(v_Clob, true, dbms_lob.call);
		dbms_lob.createtemporary(v_Bad_Result, true, dbms_lob.call);
		dbms_lob.createtemporary(v_Good_Result, true, dbms_lob.call);

		v_Enclosed_By := p_Enclosed_By;

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
		v_New_Line := chr(13) || chr(10);
		v_Offset   := dbms_lob.instr(v_Clob, v_New_Line);
		if v_Offset = 0 or v_Offset >= g_linemaxsize then
			-- try line delimiter lf
			v_New_Line := chr(10);
			v_Offset   := dbms_lob.instr(v_Clob, v_New_Line);
		end if;
		if v_Offset = 0 or v_Offset >= g_linemaxsize then
			-- try line delimiter cr
			v_New_Line := chr(13);
			v_Offset   := dbms_lob.instr(v_Clob, v_New_Line);
		end if;
		if v_Offset = 0 or v_Offset >= g_linemaxsize  then
			p_Message := g_msg_line_delimiter;
			return;
		end if;
		-- set Column Delimiter
		if p_Column_Delimiter IS NULL then 
			v_Column_Delimiter := Find_Column_Delimiter(v_Clob, v_New_Line);
		else 
			v_Column_Delimiter :=
				case p_Column_Delimiter
				when '\t' then chr(9)
				else p_Column_Delimiter end;
		end if;
		-- probe Column Delimiter
		v_Row_Line := RTRIM(dbms_lob.substr( v_clob, v_Offset - 1, 1 ), v_Column_Delimiter);
		v_Column_Cnt := 1 + LENGTH(v_Row_Line) - LENGTH(REPLACE(v_Row_Line, v_Column_Delimiter));
		if v_Column_Cnt = 1 and p_Column_Delimiter IS NOT NULL then
			p_Message := g_msg_separator_head;
			return;
		end if;
		-- probe optionally enclosed by
		if SUBSTR(v_Row_Line, 1, 1) = v_Enclosed_By
		and SUBSTR(RTRIM(v_Row_Line, v_Column_Delimiter||' '), -1, 1) = v_Enclosed_By
		and LENGTH(v_Row_Line) > 2 then
			v_Column_Delimiter 	:= v_Enclosed_By || v_Column_Delimiter || v_Enclosed_By;
		else
			v_Enclosed_By := NULL;
		end if;

		for c_rows in (
			SELECT S.Column_Value, ROWNUM Line_No
			FROM TABLE( import_filter_plugin.Split_Clob(v_Clob, p_Enclosed_By, v_New_Line) ) S
		)
		loop
			if c_rows.Column_Value IS NOT NULL then
				v_Row_Line := case when v_Enclosed_By IS NOT NULL
								then SUBSTR(c_rows.Column_Value, 2, LENGTH(c_rows.Column_Value)-2)
								else c_rows.Column_Value end
							|| v_New_Line;
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
		v_exec_result.execution_skipped := false;
		if v_Show_Message = 'Y' then
			if v_Message = 'OK' then
				v_exec_result.success_message := APEX_LANG.LANG (
					p_primary_text_string => g_msg_process_success,
					p0 => v_Good_Rows_Cnt,
					p1 => v_Bad_Rows_Cnt,
					p_primary_language => 'en'
				);
			elsif v_Message = 'OK' and v_Rows_Cnt = 0 then
				Apex_Error.Add_Error (
					p_message  => Apex_Lang.Lang(g_msg_no_data_found, p_primary_language => 'en'),
					p_display_location => apex_error.c_inline_in_notification
				);				
			elsif v_Message != 'OK' then
				Apex_Error.Add_Error (
					p_message  => Apex_Lang.Lang(v_Message, p_primary_language => 'en'),
					p_display_location => apex_error.c_inline_in_notification
				);				
			end if;
		end if;
		RETURN v_exec_result;
	END Filter_Upload;
END import_filter_plugin;
/
show errors

