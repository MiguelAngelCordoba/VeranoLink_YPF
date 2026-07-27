-- liquibase formatted sql
-- changeset VERANOLINK:1785188155459 stripComments:false  logicalFilePath:base-release\veranolink\package_specs\vl_pkg_convert_blobclob.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/vl_pkg_convert_blobclob.sql:null:a005bfced0a7705664d7c2be116d95cb86064414:create

create or replace package veranolink.vl_pkg_convert_blobclob as
    function clob_to_blob (
        p_data in clob
    ) return blob;

    function clobfromblob (
        p_blob blob
    ) return clob;

end vl_pkg_convert_blobclob;
/

