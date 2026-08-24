-- liquibase formatted sql
-- changeset VERANOLINK:1787600192169 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\indexes\ix_tbl_wbs_wbsid_upd.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/ix_tbl_wbs_wbsid_upd.sql:null:a93dfd7edceebe56abbc72912ccebfce961f6972:create

create index veranolink.ix_tbl_wbs_wbsid_upd on
    veranolink.tbl_wbs (
        wbs_id,
        updatedate
    );

