-- liquibase formatted sql
-- changeset VERANOLINK:1785188144687 stripComments:false  logicalFilePath:base-release\veranolink\package_bodies\vl_pkg_crud_company.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/vl_pkg_crud_company.sql:null:1220fe6419e9aa9b37d434b35b45d800111d688b:create

create or replace package body veranolink.vl_pkg_crud_company is

    procedure new_company (
        names       varchar2,
        country     number,
        short_names varchar2
    ) as

        alias_name          varchar2(100);
        validator           number;
        execute_create_user varchar2(4000);
        l_roles_arr         owa.vc_arr;
        l_modules_arr       owa.vc_arr;
        l_patterns_arr      owa.vc_arr;
    begin
        alias_name := upper(short_names);
        insert into vl_companies (
            name,
            vl_id_country,
            created_date,
            short_name
        ) values
            ( names,
              country,
              current_date,
              alias_name );

        execute immediate 'CREATE USER '
                          || alias_name
                          || ' IDENTIFIED BY '
                          || alias_name;
        execute immediate 'alter user '
                          || alias_name
                          || ' default tablespace apex quota unlimited on apex';
        commit;
        begin
            ords.create_role(p_role_name => 'ROL_' || alias_name);
            commit;
            ords.define_module(
                p_module_name => 'MODULE_' || alias_name,
                p_base_path   => lower(alias_name)
            );

            commit;
            l_roles_arr(1) := 'ROL_' || alias_name;
            l_modules_arr(1) := 'MODULE_' || alias_name;
            ords.define_privilege(
                p_privilege_name => 'PRIVILEGE_' || alias_name,
                p_roles          => l_roles_arr,
                p_patterns       => l_patterns_arr,
                p_modules        => l_modules_arr,
                p_label          => 'PRIVILEGE_' || alias_name,
                p_description    => 'Privilegios para ' || alias_name
            );

            commit;
        end;

    end;

    procedure update_company (
        p_name          varchar2,
        p_country       number,
        p_vl_id_company number,
        short_names     varchar2
    ) as
    begin
        update vl_companies
        set
            name = p_name,
            vl_id_country = p_country,
            short_name = short_names
        where
            vl_id_company = p_vl_id_company;

    end;

    procedure delete_company (
        p_vl_id_company number,
        short_names     varchar2
    ) as

        alias_name          varchar2(100);
        validator           number;
        execute_create_user varchar2(4000);
        l_roles_arr         owa.vc_arr;
        l_modules_arr       owa.vc_arr;
        l_patterns_arr      owa.vc_arr;
    begin
        alias_name := upper(short_names);
        delete from vl_companies
        where
            vl_id_company = p_vl_id_company;

        ords.delete_privilege(p_name => 'PRIVILEGE_' || alias_name);
        ords.delete_module(p_module_name => 'MODULE_' || alias_name);
        ords.delete_role(p_role_name => 'ROL_' || alias_name);

    --    EXECUTE IMMEDIATE 'DROP USER ' || ALIAS_NAME || ' CASCADE';
    --    COMMIT;
    end;

end vl_pkg_crud_company;
/

