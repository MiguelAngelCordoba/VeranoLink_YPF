-- liquibase formatted sql
-- changeset VERANOLINK:1787600191919 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\indexes\idx_tbl_activity_project.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_tbl_activity_project.sql:null:3016f657dd1b4b9eb93558c1333461435af035be:create

create index veranolink.idx_tbl_activity_project on
    veranolink.tbl_activity (
        project_id
    );

