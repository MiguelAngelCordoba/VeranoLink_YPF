create or replace package body veranolink.vl_pkg_utl_base64 is

    function vl_fn_decode_base64 (
        p_clob_in in clob
    ) return blob is

        v_blob           blob;
        v_result         blob;
        v_offset         integer;
        v_buffer_size    binary_integer := 48;
        v_buffer_varchar varchar2(48);
        v_buffer_raw     raw(48);
    begin
        if p_clob_in is null then
            return null;
        end if;
        dbms_lob.createtemporary(v_blob, true);
        v_offset := 1;
        for i in 1..ceil(dbms_lob.getlength(p_clob_in) / v_buffer_size) loop
            dbms_lob.read(p_clob_in, v_buffer_size, v_offset, v_buffer_varchar);
            v_buffer_raw := utl_raw.cast_to_raw(v_buffer_varchar);
            v_buffer_raw := utl_encode.base64_decode(v_buffer_raw);
            dbms_lob.writeappend(v_blob,
                                 utl_raw.length(v_buffer_raw),
                                 v_buffer_raw);
            v_offset := v_offset + v_buffer_size;
        end loop;

        v_result := v_blob;
        dbms_lob.freetemporary(v_blob);
        return v_result;
    end vl_fn_decode_base64;

    function vl_fn_encode_base64 (
        p_blob_in in blob
    ) return clob is

        v_clob           clob;
        v_result         clob;
        v_offset         integer;
        v_chunk_size     binary_integer := ( 48 / 4 ) * 3;
        v_buffer_varchar varchar2(48);
        v_buffer_raw     raw(48);
    begin
        if p_blob_in is null then
            return null;
        end if;
        dbms_lob.createtemporary(v_clob, true);
        v_offset := 1;
        for i in 1..ceil(dbms_lob.getlength(p_blob_in) / v_chunk_size) loop
            dbms_lob.read(p_blob_in, v_chunk_size, v_offset, v_buffer_raw);
            v_buffer_raw := utl_encode.base64_encode(v_buffer_raw);
            v_buffer_varchar := utl_raw.cast_to_varchar2(v_buffer_raw);
            dbms_lob.writeappend(v_clob,
                                 length(v_buffer_varchar),
                                 v_buffer_varchar);
            v_offset := v_offset + v_chunk_size;
        end loop;

        v_result := v_clob;
        dbms_lob.freetemporary(v_clob);
        return v_result;
    end vl_fn_encode_base64;

    function encode_number_to_base64 (
        p_number in number
    ) return varchar2 is
        l_raw    raw(32767);
        l_base64 raw(32767);
    begin
        l_raw := utl_raw.cast_to_raw(to_char(p_number));
        l_base64 := utl_encode.base64_encode(l_raw);
  
  -- Convert the Base64 RAW value to VARCHAR2 and return
        return utl_raw.cast_to_varchar2(l_base64);
    end;

end vl_pkg_utl_base64;
/


-- sqlcl_snapshot {"hash":"671e223dac473958a07aa0385671f0c69a5b33bd","type":"PACKAGE_BODY","name":"VL_PKG_UTL_BASE64","schemaName":"VERANOLINK","sxml":""}