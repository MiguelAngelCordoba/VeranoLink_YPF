-- liquibase formatted sql
-- changeset VERANOLINK:1788793861850 stripComments:false  logicalFilePath:stage\veranolink\jobs\job_integracion_diaria.sql
-- sqlcl_snapshot db/src/database/veranolink/jobs/job_integracion_diaria.sql:278cd6205f88c2e6082bc31ebfc0de7fe6733ebd:b7971f98ba46d30f0301547c21f45d85576090f8:alter

begin
    dbms_scheduler.disable('VERANOLINK.JOB_INTEGRACION_DIARIA');
    dbms_scheduler.set_attribute(
        name      => 'VERANOLINK.JOB_INTEGRACION_DIARIA',
        attribute => 'comments',
        value     => 'Integracion nocturna OPC -> Sequence: proyectos, WBS, actividades - Creación y actualización'
    );

    dbms_scheduler.set_attribute(
        name      => 'VERANOLINK.JOB_INTEGRACION_DIARIA',
        attribute => 'repeat_interval',
        value     => 'FREQ=DAILY; interval=1;'
    );

    dbms_scheduler.set_attribute(
        name      => 'VERANOLINK.JOB_INTEGRACION_DIARIA',
        attribute => 'start_date',
        value     => timestamp '2026-09-03 22:00:00.0'
    );

    dbms_scheduler.enable('VERANOLINK.JOB_INTEGRACION_DIARIA');
end;
/

