create or replace package veranolink.vl_pkg_crud_user is
    function new_user (
        p_name     varchar2,
        p_email    varchar2,
        p_password varchar2,
        p_company  number,
        p_rol      number
    ) return number;

    procedure update_user (
        p_name       varchar2,
        p_email      varchar2,
        p_company    number,
        p_rol        number,
        p_state      number,
        p_vl_id_user number
    );

    procedure update_user_pass (
        p_new_pass   varchar2,
        p_vl_id_user number
    );

    procedure update_user_sources (
        p_array varchar2,
        p_user  number
    );

    procedure delete_user (
        user_id in number
    );

end vl_pkg_crud_user;
/


-- sqlcl_snapshot {"hash":"015a56813cc91ec4a3b84129fa0b3d5022abcbec","type":"PACKAGE_SPEC","name":"VL_PKG_CRUD_USER","schemaName":"VERANOLINK","sxml":""}