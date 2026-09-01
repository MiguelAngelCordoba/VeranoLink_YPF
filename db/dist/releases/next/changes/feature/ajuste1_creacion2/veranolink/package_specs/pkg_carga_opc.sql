-- liquibase formatted sql
-- changeset VERANOLINK:1787600191956 stripComments:false  logicalFilePath:feature\ajuste1_creacion2\veranolink\package_specs\pkg_carga_opc.sql
-- sqlcl_snapshot db/src/database/veranolink/package_specs/pkg_carga_opc.sql:null:a2d4ee4d1da6745a6b550124a32a13b8de003bef:create

create or replace package veranolink.pkg_carga_opc as

    -- Carga los proyectos marcados con el UDF 'Integracion Sequence' = TRUE.
    -- Aplica reglas de contrato (unicidad, congelamiento por cambio) y pobla
    -- WORKSPACE_CODE, necesario para los endpoints de linea base.
    procedure cargar_proyectos;

    -- Carga la jerarquia WBS del cronograma actual filtrada por Fase=Construccion.
    -- Es la estructura base desde la que se reconstruye la jerarquia de cada
    -- linea base y desde la que se deriva el path vigente en Ecosys.
    procedure cargar_wbs;

    -- Registra las lineas base marcadas como ORIGINAL o CURRENT en cada proyecto
    -- y mantiene su vigencia. Es el gate del flujo de creacion.
    procedure cargar_baselines;

    -- Consume las actividades de la linea base vigente de cada proyecto.
    -- Fuente del flujo de CREACION hacia Sequence.
    procedure cargar_actividades_baseline;

    -- Consume el cronograma actual de forma incremental por updateDate.
    -- Fuente del flujo de ACTUALIZACION (Hours y fechas CB).
    procedure cargar_actividades;

end pkg_carga_opc;
/

