-- liquibase formatted sql
-- changeset VERANOLINK:1788372754167 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\indexes\idx_log_lote_result.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_log_lote_result.sql:null:d9b966326e55ae3db275332b33e4fc7dcf12f905:create

create index veranolink.idx_log_lote_result on
    veranolink.log_lote (
        resultado,
        fecha_ejecucion
    desc );

