-- liquibase formatted sql
-- changeset VERANOLINK:1788372754314 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\indexes\ix_tbl_wbs_bl_prj_bl.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/ix_tbl_wbs_bl_prj_bl.sql:null:026816207a6864d8464742e7563ef06833989a61:create

create index veranolink.ix_tbl_wbs_bl_prj_bl on
    veranolink.tbl_wbs_baseline (
        project_id,
        project_baseline_id
    );

