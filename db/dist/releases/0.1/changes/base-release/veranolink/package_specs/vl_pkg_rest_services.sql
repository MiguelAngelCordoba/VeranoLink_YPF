-- liquibase formatted sql
-- changeset VERANOLINK:1785188155581 stripComments:false  logicalFilePath:base-release\veranolink\package_specs\vl_pkg_rest_services.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/vl_pkg_rest_services.sql:null:10e0e64f257d3b357a49178a66d8099a57b707dc:create

create or replace package veranolink.vl_pkg_rest_services as
    function vl_fn_rest_gettoken (
        iv_alias       in varchar2,
        iv_company     in varchar2,
        iv_environment in number
    ) return clob;

    function vl_fn_rest_services (
        iv_filterurl     in varchar2 default null,
        iv_bodyrequest   in clob default null,
        iv_body_blob     in blob default null,
        iv_projectid     in varchar2 default null,
        iv_alias         in varchar2,
        iv_company       in varchar2,
        iv_methodcontext in number,
        iv_environment   in number
    ) return clob;

    function vl_extract_api_response (
        iv_param_json   clob,
        iv_cod_context  number,
        iv_company_name varchar2,
        iv_environment  number
    ) return clob;

    function vl_sp_json_mgmn (
        iv_filterurl     in varchar2 default null,
        iv_bodyrequest   in varchar2 default null,
        iv_projectid     in varchar2 default null,
        iv_alias         in varchar2,
        iv_company       in varchar2,
        iv_methodcontext in number,
        iv_environment   in number
    ) return varchar2;

    procedure vl_audit_logs (
        iv_path_context       in number,
        iv_company_shortname  in varchar2,
        iv_aplication         in varchar2,
        iv_vl_audit_log       in varchar2,
        iv_vl_status_code     in number,
        iv_vl_log_description in varchar2,
        iv_vl_parameters      in clob,
        iv_timestamp          in timestamp,
        iv_vl_method          in varchar2,
        iv_name_api           in varchar2
    );

  -- Función para validar fuentes ingresadas por el usuario.
    function vl_fn_validate_source (
        iv_alias       in varchar2,
        iv_company     in varchar2,
        iv_environment in number,
        iv_user_base64 in varchar2,
        iv_endpoint    in varchar2
    ) return boolean;

end vl_pkg_rest_services;
/

