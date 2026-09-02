-- liquibase formatted sql
-- changeset veranolink:1788300191255 stripComments:false  logicalFilePath:fix\6\veranolink\comments\tbl_project.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/tbl_project.sql:null:773eef6b7f5d89f8e0aa4653c0c7dd446fe3f5a9:create

comment on column veranolink.tbl_project.estado_integracion is
    'Semaforo de integracion. OK = procede a WBS/Actividad. DUPLICADO = otro PROJECT_ID tiene el mismo Contract Number, no procede. CONTRATO_CAMBIADO = el Contract Number cambio respecto a lo que ya estaba guardado, la fila NO se actualiza esta corrida y queda congelada hasta correccion manual en OPC.'
    ;

comment on column veranolink.tbl_project.workspace_code is
    'ID del espacio de trabajo OPC que contiene el proyecto. Requerido junto con PROJECT_CODE por el endpoint View Activities by Baseline'
    ;

