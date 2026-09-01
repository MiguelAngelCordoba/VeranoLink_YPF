-- liquibase formatted sql
-- changeset VERANOLINK:1787600191918 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\indexes\idx_tbl_activity_activity.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_tbl_activity_activity.sql:null:b6d73bb11388251e55e3e523e1faca29d5d614a1:create

create index veranolink.idx_tbl_activity_activity on
    veranolink.tbl_activity (
        activity_id
    );

