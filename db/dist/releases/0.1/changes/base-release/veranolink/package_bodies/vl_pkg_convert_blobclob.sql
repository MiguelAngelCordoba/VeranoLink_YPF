-- liquibase formatted sql
-- changeset VERANOLINK:1785188144723 stripComments:false  logicalFilePath:base-release\veranolink\package_bodies\vl_pkg_convert_blobclob.sql
-- sqlcl_snapshot db/src/database/veranolink/package_bodies/vl_pkg_convert_blobclob.sql:null:538c17e36f5ad84741e4f58f6ad363cd69f80118:create

create or replace package body veranolink.vl_pkg_convert_blobclob as

    function clobfromblob (
        p_blob blob
    ) return clob is

        l_clob         clob;
        l_dest_offsset integer := 1;
        l_src_offsset  integer := 1;
        l_lang_context integer := dbms_lob.default_lang_ctx;
        l_warning      integer;
    begin
        if p_blob is null then
            return null;
        end if;
        dbms_lob.createtemporary(
            lob_loc => l_clob,
            cache   => false
        );
        dbms_lob.converttoclob(
            dest_lob     => l_clob,
            src_blob     => p_blob,
            amount       => dbms_lob.lobmaxsize,
            dest_offset  => l_dest_offsset,
            src_offset   => l_src_offsset,
            blob_csid    => dbms_lob.default_csid,
            lang_context => l_lang_context,
            warning      => l_warning
        );

        return l_clob;
    end;

    function clob_to_blob (
        p_data in clob
    ) return blob as

        l_blob         blob;
        l_dest_offset  pls_integer := 1;
        l_src_offset   pls_integer := 1;
        l_lang_context pls_integer := dbms_lob.default_lang_ctx;
        l_warning      pls_integer := dbms_lob.warn_inconvertible_char;
    begin
        dbms_lob.createtemporary(
            lob_loc => l_blob,
            cache   => true
        );
        dbms_lob.converttoblob(
            dest_lob     => l_blob,
            src_clob     => p_data,
            amount       => dbms_lob.lobmaxsize,
            dest_offset  => l_dest_offset,
            src_offset   => l_src_offset,
            blob_csid    => dbms_lob.default_csid,
            lang_context => l_lang_context,
            warning      => l_warning
        );

        return l_blob;
    end;

end vl_pkg_convert_blobclob;
/

