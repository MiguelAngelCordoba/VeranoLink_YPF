create or replace package veranolink.vl_pkg_convert_blobclob as
    function clob_to_blob (
        p_data in clob
    ) return blob;

    function clobfromblob (
        p_blob blob
    ) return clob;

end vl_pkg_convert_blobclob;
/


-- sqlcl_snapshot {"hash":"a005bfced0a7705664d7c2be116d95cb86064414","type":"PACKAGE_SPEC","name":"VL_PKG_CONVERT_BLOBCLOB","schemaName":"VERANOLINK","sxml":""}