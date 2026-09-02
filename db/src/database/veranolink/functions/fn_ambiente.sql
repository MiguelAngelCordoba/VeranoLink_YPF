create or replace function veranolink.fn_ambiente return number is

    c_db_productivo  constant varchar2(128) := 'YPF_VL_PROD';
    c_db_stage       constant varchar2(128) := 'YPF_VL_STGE';
    c_env_productivo constant number := 1;   -- VL_TYPES_ENVIRONMENT: 'Productivo'
    c_env_pruebas    constant number := 2;   -- VL_TYPES_ENVIRONMENT: 'Pruebas'

    l_db_name        varchar2(128);
    l_ambiente       number;
begin
    l_db_name := upper(trim(sys_context('USERENV', 'DB_NAME')));
    if l_db_name = c_db_productivo then
        l_ambiente := c_env_productivo;
    elsif l_db_name = c_db_stage then
        l_ambiente := c_env_pruebas;
    else
        raise_application_error(-20050,
                                'Ambiente no reconocido. SYS_CONTEXT(USERENV, DB_NAME) devolvio "'
                                || nvl(l_db_name, '<NULL>')
                                || '". Valores esperados: '
                                || c_db_productivo
                                || ' o '
                                || c_db_stage
                                || '. Si se agrego una base nueva, debe registrarse en FN_AMBIENTE.');
    end if;

    return l_ambiente;
end fn_ambiente;
/


-- sqlcl_snapshot {"hash":"befc43bf3232bcc1702254b51d52a380219b2037","type":"FUNCTION","name":"FN_AMBIENTE","schemaName":"VERANOLINK","sxml":""}