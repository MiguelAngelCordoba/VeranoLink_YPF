-- liquibase formatted sql
-- changeset VERANOLINK:1788372754302 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\indexes\ix_tbl_wbs_project_upd.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/ix_tbl_wbs_project_upd.sql:null:b81f701f29b9d09a716e9936090d3500dd7c05bd:create

create index veranolink.ix_tbl_wbs_project_upd on
    veranolink.tbl_wbs (
        project_id,
        updatedate
    );

