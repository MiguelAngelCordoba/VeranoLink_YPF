-- liquibase formatted sql
-- changeset veranolink:1788372754122 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\comments\tbl_project_baseline.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/tbl_project_baseline.sql:null:351c81db4ec5a0a3cfdd9a24fbad7598f15da1d7:create

comment on table veranolink.tbl_project_baseline is
    'Historico de lineas base que han estado marcadas como ORIGINAL o CURRENT en OPC. Las LB con tipo vacio nunca ingresan. Cada fila representa una LB que en algun momento fue marcada; si VIGENTE=N significa que fue desmarcada en OPC pero se conserva por trazabilidad'
    ;

comment on column veranolink.tbl_project_baseline.baseline_name is
    'Nombre de la LB en OPC. Solo trazabilidad, no se usa para consumir';

comment on column veranolink.tbl_project_baseline.baseline_type is
    'ORIGINAL o CURRENT. Es el valor que se envia al parametro baselineType del endpoint View Activities by Baseline (el baselineName no es necesario)'
    ;

comment on column veranolink.tbl_project_baseline.fecha_desmarcado is
    'Momento en que se detecto que la LB dejo de estar marcada como ORIGINAL o CURRENT en OPC';

comment on column veranolink.tbl_project_baseline.intentos is
    'Numero de veces que se ha consumido esta LB. Se incrementa en cada reintento por objetos fallidos. Informativo, no corta el reproceso'
    ;

comment on column veranolink.tbl_project_baseline.project_baseline_id is
    'ID estable de la linea base en OPC. Es la llave de deteccion de cambio: si llega un valor distinto al vigente, hay nueva linea base que consumir'
    ;

comment on column veranolink.tbl_project_baseline.vigente is
    'Y = la LB sigue marcada con ese tipo en OPC. N = fue desmarcada. Sin filas vigentes el proyecto queda pausado: no se consume ni se envia nada'
    ;

