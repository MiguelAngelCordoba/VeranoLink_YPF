-- liquibase formatted sql
-- changeset VERANOLINK:1788372754340 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\indexes\ix_tbl_act_bl_prj_bl.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/ix_tbl_act_bl_prj_bl.sql:null:6402ba8956e435b6ac5dc8678c7279e62acbbe64:create

create index veranolink.ix_tbl_act_bl_prj_bl on
    veranolink.tbl_activity_baseline (
        project_id,
        project_baseline_id
    );

