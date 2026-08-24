-- liquibase formatted sql
-- changeset VERANOLINK:1787600192769 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\package_specs\pkg_envio_sequence.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/pkg_envio_sequence.sql:null:8e18196f3ed6d2bf2cc508e7dae7ee9117514be4:create

create or replace package veranolink.pkg_envio_sequence as

    -- Crea en Ecosys los objetos pendientes (VIEW_SEQUENCE_CREATE).
    -- Por proyecto envia DOS peticiones: primero WBS en orden jerarquico
    -- (el padre debe existir antes que el hijo), luego actividades.
    procedure enviar_creacion;

    -- Actualiza en Ecosys los objetos que cambiaron (VIEW_SEQUENCE_UPDATE).
    -- Por proyecto envia UNA SOLA peticion con WBS y actividades juntas:
    -- Ecosys resuelve todos los paths del array contra el estado previo al
    -- request, por lo que todos deben ir con el path anterior al cambio.
    procedure enviar_actualizacion;

    -- Orquestacion nocturna completa.
    procedure integracion_diaria;

end pkg_envio_sequence;
/

