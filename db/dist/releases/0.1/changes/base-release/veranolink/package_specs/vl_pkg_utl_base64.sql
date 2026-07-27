-- liquibase formatted sql
-- changeset VERANOLINK:1785188155672 stripComments:false  logicalFilePath:base-release\veranolink\package_specs\vl_pkg_utl_base64.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/vl_pkg_utl_base64.sql:null:3299f6046f0d419d5898f6d1476a4ce83d8e934a:create

create or replace package veranolink.vl_pkg_utl_base64 is
    function vl_fn_decode_base64 (
        p_clob_in in clob
    ) return blob;

    function vl_fn_encode_base64 (
        p_blob_in in blob
    ) return clob;

    function encode_number_to_base64 (
        p_number in number
    ) return varchar2;

end vl_pkg_utl_base64;
/

