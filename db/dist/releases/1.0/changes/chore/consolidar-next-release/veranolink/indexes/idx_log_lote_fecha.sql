-- liquibase formatted sql
-- changeset VERANOLINK:1788372754179 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\indexes\idx_log_lote_fecha.sql
-- sqlcl_snapshot db/src/database/veranolink/indexes/idx_log_lote_fecha.sql:null:50391a1c6c3f6996551477479c8a2e3b7f4fea97:create

create index veranolink.idx_log_lote_fecha on
    veranolink.log_lote (
        fecha_ejecucion
    desc );

