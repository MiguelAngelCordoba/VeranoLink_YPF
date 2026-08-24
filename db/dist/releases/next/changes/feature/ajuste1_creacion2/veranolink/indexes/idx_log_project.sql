-- liquibase formatted sql
-- changeset VERANOLINK:1787600191923 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\indexes\idx_log_project.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_log_project.sql:null:be9856583c1f61006abb2a5e161df195f5b3cec0:create

create index veranolink.idx_log_project on
    veranolink.log_opc_sequence (
        project_id,
        resultado
    );

