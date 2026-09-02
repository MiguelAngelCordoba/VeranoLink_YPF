-- liquibase formatted sql
-- changeset VERANOLINK:1788300191311 stripComments:false  logicalFilePath:fix\6\veranolink\indexes\ix_tbl_prj_bl_vigente.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/ix_tbl_prj_bl_vigente.sql:null:22375e5fa10688bee05a4b11bdb75ea55cbcd9af:create

create index veranolink.ix_tbl_prj_bl_vigente on
    veranolink.tbl_project_baseline (
        vigente,
        project_id
    );

