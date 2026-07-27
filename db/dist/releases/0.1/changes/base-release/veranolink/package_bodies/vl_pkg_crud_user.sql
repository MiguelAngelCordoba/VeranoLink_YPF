-- liquibase formatted sql
-- changeset VERANOLINK:1785188144640 stripComments:false  logicalFilePath:base-release\veranolink\package_bodies\vl_pkg_crud_user.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/vl_pkg_crud_user.sql:null:fa2b84aa30bd12d0b5932cad1429a3b267686728:create

create or replace package body veranolink.vl_pkg_crud_user is

    function new_user (
        p_name     varchar2,
        p_email    varchar2,
        p_password varchar2,
        p_company  number,
        p_rol      number
    ) return number is
        pass      vl_users.password%type;
        v_id_user number;
    begin
        select
            standard_hash(p_password, 'SHA256')
        into pass
        from
            dual;
    
        -- Insertamos el nuevo usuario
        insert into vl_users (
            name,
            email,
            password,
            vl_id_company,
            vl_id_rol,
            created_date,
            state
        ) values
            ( p_name,
              upper(p_email),
              pass,
              p_company,
              p_rol,
              current_date,
              1 )
        returning vl_id_user into v_id_user;  -- Obtenemos el ID del usuario recién creado

        return v_id_user;  -- Retornamos el ID del nuevo usuario
    end;

    procedure update_user (
        p_name       varchar2,
        p_email      varchar2,
        p_company    number,
        p_rol        number,
        p_state      number,
        p_vl_id_user number
    ) as
        pass vl_users.password%type;
    begin
        update vl_users
        set
            name = p_name,
            email = p_email,
            vl_id_company = p_company,
            vl_id_rol = p_rol,
            state = p_state
        where
            vl_id_user = p_vl_id_user;

    end;

    procedure update_user_pass (
        p_new_pass   varchar2,
        p_vl_id_user number
    ) as
        pass vl_users.password%type;
    begin
        select
            standard_hash(p_new_pass, 'SHA256')
        into pass
        from
            dual;

        update vl_users
        set
            password = pass
        where
            vl_id_user = p_vl_id_user;

    end;

    procedure update_user_sources (
        p_array varchar2,
        p_user  number
    ) as

        cursor c_get_user_assign (
            vci_source number,
            vci_user   number
        ) is
        select
            vl_assign_state as estado
        from
            vl_source_assigns
        where
                id_vl_user = vci_user
            and id_vl_source_environment = vci_source;

        l_getassigns   c_get_user_assign%rowtype;
        l_validassigns boolean;
    begin
        delete from vl_source_assigns
        where
            id_vl_user = p_user;

        for n in (
            with tbl ( str ) as (
                select
                    p_array
                from
                    dual
            )
            select
                regexp_substr(str, '(.*?)(:|$)', 1, level, null,
                              1) element
            from
                tbl
            connect by
                level <= regexp_count(str, ':') + 1
        ) loop
            open c_get_user_assign(n.element, p_user);
            fetch c_get_user_assign into l_getassigns;
            l_validassigns := c_get_user_assign%found;
            close c_get_user_assign;
            if
                l_validassigns = false
                and p_array is not null
            then
                insert into vl_source_assigns values
                    ( p_user,
                      n.element,
                      1 );

            end if;

        end loop;

    end;

    procedure delete_user (
        user_id in number
    ) is
        v_find_assigns number;
    begin
        select
            count(*)
        into v_find_assigns
        from
            vl_source_assigns vsa
        where
            vsa.id_vl_user = user_id;

        if v_find_assigns > 0 then
            delete from vl_source_assigns
            where
                id_vl_user = user_id;

        end if;
        delete from vl_users
        where
            vl_id_user = user_id;

        commit;
    end;

end vl_pkg_crud_user;
/

