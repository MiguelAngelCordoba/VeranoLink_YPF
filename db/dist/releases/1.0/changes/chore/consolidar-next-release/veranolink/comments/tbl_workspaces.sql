-- liquibase formatted sql
-- changeset veranolink:1788372754228 stripComments:false  logicalFilePath:chore\consolidar-next-release\veranolink\comments\tbl_workspaces.sql
-- sqlcl_snapshot db/src/database/veranolink/comments/tbl_workspaces.sql:null:f9b1c47e20f4e54c5458101e1c624f4f354bdfe3:create

comment on table veranolink.tbl_workspaces is
    'Espacios de trabajo de OPC correspondientes al ambiente actual (productivo o no productivo, segun FN_AMBIENTE). Se reconstruye completa cada corrida: refleja siempre el estado vivo de OPC, no guarda historia. Un proyecto solo se integra si su WORKSPACE_ID existe en esta tabla.'
    ;

comment on column veranolink.tbl_workspaces.fecha_sincronizacion is
    'Momento de la corrida que poblo esta fila. Todas las filas comparten el mismo valor por reconstruirse en una sola transaccion. Permite detectar una tabla obsoleta.'
    ;

comment on column veranolink.tbl_workspaces.is_production is
    'Y si el espacio es productivo en OPC, N si no lo es. Evidencia de que el filtro por ambiente se aplico correctamente: en Stage todas las filas deben ser N y en Produccion todas Y. Un valor mezclado indica falla en la carga.'
    ;

comment on column veranolink.tbl_workspaces.workspace_code is
    'Codigo visible del espacio en OPC (campo workspaceCode). Unico en todo el tenant. Solo para lectura humana y diagnostico.';

comment on column veranolink.tbl_workspaces.workspace_id is
    'ID interno del espacio de trabajo en OPC (campo workspaceId). Llave de validacion contra TBL_PROJECT.WORKSPACE_ID. Es inmutable en OPC, a diferencia del code.'
    ;

