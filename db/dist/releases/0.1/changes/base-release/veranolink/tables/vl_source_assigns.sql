-- liquibase formatted sql
-- changeset VERANOLINK:1785188156136 stripComments:false  logicalFilePath:base-release\veranolink\tables\vl_source_assigns.sql
-- sqlcl_snapshot db/src/database/veranolink/tables/vl_source_assigns.sql:null:b9264a6761ab8550961d1297d0a54c4d5a72d087:create

create table veranolink.vl_source_assigns (
    id_vl_user               number,
    id_vl_source_environment number,
    vl_assign_state          number
);

