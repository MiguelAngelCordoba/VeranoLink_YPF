create or replace function veranolink.convert_blob_to_clob (
    p_log_id in number
) return clob is

    v_blob        blob;
    v_clob        clob;
    l_dest_offset integer := 1;
    l_src_offset  integer := 1;
    l_lang_ctx    integer := dbms_lob.default_lang_ctx;
    l_warning     integer;
begin
    -- Obtener el BLOB
    select
        binary_output
    into v_blob
    from
        user_scheduler_job_run_details
    where
        log_id = p_log_id;

    -- Crear un CLOB temporal
    dbms_lob.createtemporary(v_clob, true);

    -- Convertir el BLOB a CLOB
    dbms_lob.converttoclob(
        dest_lob     => v_clob,
        src_blob     => v_blob,
        amount       => dbms_lob.lobmaxsize,
        dest_offset  => l_dest_offset,
        src_offset   => l_src_offset,
        blob_csid    => dbms_lob.default_csid,
        lang_context => l_lang_ctx,
        warning      => l_warning
    );

    -- Retornar el CLOB convertido
    return v_clob;
exception
    when no_data_found then
        return 'Error: No se encontró el registro.';
    when others then
        return 'Error: ' || sqlerrm;
end;
/


-- sqlcl_snapshot {"hash":"9467017408fb2086c7e615e7f65e19431af2b0be","type":"FUNCTION","name":"CONVERT_BLOB_TO_CLOB","schemaName":"VERANOLINK","sxml":""}