-- liquibase formatted sql
-- changeset veranolink:1788372754094 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\comments\tbl_activity_baseline.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/tbl_activity_baseline.sql:null:b104e84ee5c953dc01945cb91fd1f00c3d6af958:create

comment on table veranolink.tbl_activity_baseline is
    'Historico (append-only) de actividades por linea base. Fuente del flujo de creacion hacia Sequence. Cada snapshot de LB se inserta completo, por lo que una misma ACTIVITY_ID aparece una vez por cada LB en la que estuvo presente'
    ;

comment on column veranolink.tbl_activity_baseline.activity_id is
    'ID interno OPC de la actividad. Es el mismo en la linea base y en el cronograma actual, y es el valor enviado a Ecosys como ExternalID'
    ;

comment on column veranolink.tbl_activity_baseline.activity_type_opc is
    'activityType de OPC (ACTIVITY, LEVEL_OF_EFFORT, START_MILESTONE, FINISH_MILESTONE...). Trazabilidad: los hitos traen una sola fecha y la vista duplica la faltante'
    ;

comment on column veranolink.tbl_activity_baseline.bl_finish_date is
    'Fecha de fin congelada de la linea base (campo finishDate del endpoint de baseline). Se envia a Ecosys como EndDateOBCost';

comment on column veranolink.tbl_activity_baseline.bl_start_date is
    'Fecha de inicio congelada de la linea base (campo startDate del endpoint de baseline, no es la fecha viva del cronograma). Se envia a Ecosys como StartDateOBCost'
    ;

comment on column veranolink.tbl_activity_baseline.origen_carga is
    'SNAPSHOT = carga completa al detectar LB nueva. REINTENTO = carga puntual de actividades que fallaron, filtrando por activityId en el header filters'
    ;

comment on column veranolink.tbl_activity_baseline.project_baseline_id is
    'Linea base de la que provino esta version de la actividad. Permite reconstruir el contenido exacto de cualquier LB consumida';

comment on column veranolink.tbl_activity_baseline.type is
    'Tipo de linea para Ecosys. Valor fijo Work Package para actividades';

