-- liquibase formatted sql
-- changeset VERANOLINK:1785188155365 stripComments:false  logicalFilePath:base-release\veranolink\package_bodies\vl_pkg_process_custom_report.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/vl_pkg_process_custom_report.sql:null:966c413eaf3d7c599b0944fec4d93d2086e27dfb:create

create or replace package body veranolink.vl_pkg_process_custom_report as

    procedure collect_column_info (
        p_query          in clob,
        p_collection     in varchar2,
        p_detailed_stats in varchar2,
        p_company_name   in varchar2
    ) is

        l_source_query  varchar2(32767) := p_query;
        l_report_cursor integer := null;
        l_colcnt        number := 0;
        l_columns       sys.dbms_sql.desc_tab2;
        l_col_type      varchar2(32);
        l_col_max_len   number;
        l_col_nullable  varchar2(10);
        l_col_dispname  varchar2(256);
        l_sql           clob;
        l_feedback      integer;
        l_num           number;
        l_total         number;
        cursor col_csr is
        select
            seq_id,
            c001                           name,
            upper(replace(c001, ' ', '_')) clean_name,
            c002                           datatype
        from
            apex_collections
        where
            collection_name = p_collection
        order by
            seq_id;

        col_rec         col_csr%rowtype;
    begin
        l_report_cursor := sys.dbms_sql.open_cursor;
        sys.dbms_sql.parse(
            c             => l_report_cursor,
            statement     => l_source_query,
            language_flag => sys.dbms_sql.native,
            schema        => p_company_name
        );

        execute immediate 'ALTER SESSION SET CURRENT_SCHEMA = ' || p_company_name;
        sys.dbms_sql.describe_columns2(l_report_cursor, l_colcnt, l_columns);
        apex_collection.create_or_truncate_collection(p_collection_name => 'COLUMNS');
        for i in 1..l_colcnt loop
            if length(l_columns(i).col_name) > 30
            or instr(l_columns(i).col_name,
                     '''') > 0
            or instr(l_columns(i).col_name,
                     '<') > 0
            or instr(l_columns(i).col_name,
                     '>') > 0 then
                raise_application_error(-20222,
                                        '"'
                                        || l_columns(i).col_name
                                        || '" is not a valid column name for this application, and must be aliased.');
            end if;

            l_col_max_len := l_columns(i).col_max_len;
            if l_columns(i).col_type = 1 then
                l_col_type := 'VARCHAR2';
            elsif l_columns(i).col_type = 2 then
                l_col_type := 'NUMBER';
            elsif l_columns(i).col_type = 12 then
                l_col_type := 'DATE';
                l_col_max_len := 30;
            elsif l_columns(i).col_type in ( 180, 181, 231 ) then
                l_col_max_len := 30;
                l_col_type := 'TIMESTAMP';
                if l_columns(i).col_type = 231 then
                    l_col_type := 'TIMESTAMP_LTZ';
                end if;
            elsif l_columns(i).col_type = 112 then
                l_col_type := 'CLOB';
            elsif l_columns(i).col_type = 113 then
                l_col_type := 'BLOB';
            elsif l_columns(i).col_type = 96 then
                l_col_type := 'CHAR';
            else
                l_col_type := 'OTHER';
            end if;

            if l_columns(i).col_null_ok then
                l_col_nullable := 'NULL';
            else
                l_col_nullable := 'NOT NULL';
            end if;

            l_col_dispname := replace(l_columns(i).col_name,
                                      '_',
                                      ' ');
            if l_col_dispname = upper(l_col_dispname) then
                l_col_dispname := initcap(l_col_dispname);
            end if;

            apex_collection.add_member(
                p_collection_name => p_collection,
                p_c001            => l_columns(i).col_name,
                p_c004            => l_col_dispname,
                p_c002            => l_col_type,
                p_c003            => l_col_nullable,
                p_c005            => 'Y'
            );

        end loop;

        sys.dbms_sql.close_cursor(l_report_cursor);
    exception
        when others then
            if sys.dbms_sql.is_open(l_report_cursor) then
                sys.dbms_sql.close_cursor(l_report_cursor);
            end if;

            raise;
    end collect_column_info;

    procedure create_group_and_user (
        company_name  in varchar2,
        user_api      in varchar2,
        user_api_pass in varchar2
    ) is
    begin
        declare
            l_workspace_id number;
            l_group_id     number;
        begin
            l_workspace_id := apex_util.find_security_group_id(p_workspace => 'VERANOLINK');
            apex_util.set_security_group_id(p_security_group_id => l_workspace_id);
            apex_util.create_user_group(
                p_id                => null,
                p_group_name        => 'ROL_' || company_name,
                p_security_group_id => null,
                p_group_desc        => 'Creacion de grupo para la empresa '
            );

            commit;
            apex_util.set_group_group_grants(
                p_group_name          => 'ROL_' || company_name,
                p_granted_group_names => apex_t_varchar2('RESTful Services')
            );

            commit;
            l_group_id := apex_util.get_group_id(p_group_name => 'ROL_' || company_name);
            apex_util.create_user(
                p_user_name    => user_api,
                p_web_password => user_api_pass,
                p_group_ids    => l_group_id
            );

            commit;
        end;
    end create_group_and_user;

    procedure update_user_pass (
        user_api      in varchar2,
        user_old_pass in varchar2,
        user_new_pass in varchar2
    ) is
    begin
        apex_util.set_security_group_id(apex_util.find_security_group_id('VERANOLINK'));
        apex_util.reset_password(
            p_user_name    => user_api,
            p_old_password => user_old_pass,
            p_new_password => user_new_pass
        );

        commit;
    end;

    procedure run_create_user (
        company_name  in varchar2,
        user_api      in varchar2,
        user_api_pass in varchar2
    ) is
    begin
        dbms_scheduler.set_job_argument_value(
            job_name          => 'CREATE_USER_JOB',
            argument_position => 1,
            argument_value    => company_name
        );

        dbms_scheduler.set_job_argument_value(
            job_name          => 'CREATE_USER_JOB',
            argument_position => 2,
            argument_value    => user_api
        );

        dbms_scheduler.set_job_argument_value(
            job_name          => 'CREATE_USER_JOB',
            argument_position => 3,
            argument_value    => user_api_pass
        );

        dbms_scheduler.run_job(
            job_name            => 'CREATE_USER_JOB',
            use_current_session => false
        );
    end run_create_user;

    procedure run_update_user_pass (
        user_api      in varchar2,
        user_old_pass in varchar2,
        user_new_pass in varchar2
    ) is
    begin
        dbms_scheduler.set_job_argument_value(
            job_name          => 'UPDATE_USER_PASS_JOB',
            argument_position => 1,
            argument_value    => user_api
        );

        dbms_scheduler.set_job_argument_value(
            job_name          => 'UPDATE_USER_PASS_JOB',
            argument_position => 2,
            argument_value    => user_old_pass
        );

        dbms_scheduler.set_job_argument_value(
            job_name          => 'UPDATE_USER_PASS_JOB',
            argument_position => 3,
            argument_value    => user_new_pass
        );

        dbms_scheduler.run_job(
            job_name            => 'UPDATE_USER_PASS_JOB',
            use_current_session => false
        );
    end run_update_user_pass;

    procedure create_template_handler (
        company_name    in varchar2,
        name_template   in varchar2,
        api_query       in varchar2,
        api_description in varchar2,
        user_id         in number
    ) is
        v_encode varchar2(30000);
    begin
        v_encode := vl_pkg_utl_base64.encode_number_to_base64(user_id);
        apex_util.set_security_group_id(apex_util.find_security_group_id('VERANOLINK'));
        ords.define_template(
            p_module_name => 'MODULE_' || company_name,
            p_pattern     => lower(v_encode
                               || '/' || name_template)
        );

        ords.define_handler(
            p_module_name    => 'MODULE_' || company_name,
            p_pattern        => lower(v_encode
                               || '/' || name_template),
            p_method         => 'GET',
            p_source_type    => ords.source_type_collection_feed,
            p_source         => api_query,
            p_items_per_page => 0
        );

        commit;
        insert into vl_apu_tables (
            company_name,
            api_table_name,
            api_table_description,
            api_table_query,
            api_endpoint,
            id_user
        ) values
            ( upper(company_name),
              lower(name_template),
              api_description,
              api_query,
              'https://vl-epm-production.veranocloud.com.co/vl/api/'
              || lower(company_name)
              || '/'
              || lower(v_encode)
              || '/'
              || lower(name_template),
              user_id );

        commit;
    end;

    procedure update_template_handler (
        company_name  in varchar2,
        name_template in varchar2,
        api_query     in varchar2,
        id_apu_tablea in number
    ) is
    begin
        begin
            apex_util.set_security_group_id(apex_util.find_security_group_id('VERANOLINK'));
            ords.define_template(
                p_module_name => 'MODULE_' || company_name,
                p_pattern     => lower(name_template)
            );

            ords.define_handler(
                p_module_name    => 'MODULE_' || company_name,
                p_pattern        => lower(name_template),
                p_method         => 'GET',
                p_source_type    => ords.source_type_collection_feed,
                p_source         => api_query,
                p_items_per_page => 0
            );

            commit;
            update vl_apu_tables
            set
                api_table_query = to_clob(api_query)
            where
                id_vl_apu_table = id_apu_tablea;

            commit;
        end;
    end;

    procedure update_pw_user (
        user_old_pass in varchar2,
        user_new_pass in varchar2
    ) is
    begin
        apex_util.set_security_group_id(apex_util.find_security_group_id('VERANOLINK'));
        apex_util.reset_password(
            p_user_name    => 'RESTAPIUSER',
            p_old_password => user_old_pass,
            p_new_password => user_new_pass
        );

        commit;
    end update_pw_user;

    procedure run_update_pw_user (
        user_old_pass in varchar2,
        user_new_pass in varchar2
    ) is
    begin
        dbms_scheduler.set_job_argument_value(
            job_name          => 'UPDATE_PW_USER',
            argument_position => 1,
            argument_value    => user_old_pass
        );

        dbms_scheduler.set_job_argument_value(
            job_name          => 'UPDATE_PW_USER',
            argument_position => 2,
            argument_value    => user_new_pass
        );

        dbms_scheduler.run_job(
            job_name            => 'UPDATE_PW_USER',
            use_current_session => false
        );
    end run_update_pw_user;

end vl_pkg_process_custom_report;
/

