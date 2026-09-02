-- liquibase formatted sql
-- changeset veranolink:1788372754109 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\comments\tbl_activity.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/tbl_activity.sql:null:31ac445b852753b7a5d4453d63317ca2c6c6695a:create

comment on table veranolink.tbl_activity is
    'Historico (append-only) del cronograma actual de OPC. Desde el rediseno baseline-driven ya NO es fuente de creacion: alimenta unicamente el flujo de actualizacion (Hours y fechas CB)'
    ;

comment on column veranolink.tbl_activity.at_completion_labor_units is
    'atCompletionLaborUnits de OPC. Nunca es nulo. Se envia a Ecosys como Hours (HH Previstas) en el flujo de actualizacion';

comment on column veranolink.tbl_activity.finishdate is
    'finishDate del cronograma actual. Fecha prevista si la actividad no ha finalizado, fecha real si ya finalizo. Nunca nula. Se envia a Ecosys como EndDateCBCost (Tendencia Fin)'
    ;

comment on column veranolink.tbl_activity.startdate is
    'startDate del cronograma actual. Fecha prevista si la actividad no ha iniciado, fecha real si ya inicio. Nunca nula. Se envia a Ecosys como StartDateCBCost (Tendencia Inicio)'
    ;

comment on column veranolink.tbl_activity.updatedate is
    'updateDate de OPC de esta version de la actividad. Es el disparador A del flujo de actualizacion: si es mayor al UPDATE_SINCRONIZADO del ultimo envio OK, la actividad entra al lote'
    ;

