-- liquibase formatted sql
-- changeset VERANOLINK:1788300191315 stripComments:false  logicalFilePath:fix\6\veranolink\indexes\ix_tbl_act_bl_wbs.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/ix_tbl_act_bl_wbs.sql:null:ae000727ca4a96bdc817c5cfb7a44ef659ec8a7f:create

create index veranolink.ix_tbl_act_bl_wbs on
    veranolink.tbl_activity_baseline (
        wbs_id
    );

