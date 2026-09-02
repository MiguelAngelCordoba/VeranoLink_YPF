-- liquibase formatted sql
-- changeset VERANOLINK:1788372754347 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\indexes\ix_tbl_act_bl_activity.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/ix_tbl_act_bl_activity.sql:null:7e5e9565ce6459b41420149c00a1c58fcf46aa4b:create

create index veranolink.ix_tbl_act_bl_activity on
    veranolink.tbl_activity_baseline (
        activity_id,
        fecha_carga
    );

