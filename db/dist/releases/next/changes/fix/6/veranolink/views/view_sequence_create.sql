-- liquibase formatted sql
-- changeset VERANOLINK:1788300192318 stripComments:false  logicalFilePath:fix\6\veranolink\views\view_sequence_create.sql
-- sqlcl_snapshot db/src/database/veranolink/views/view_sequence_create.sql:null:45ea7d3c633048df97d07c64d7f3000e1b03242a:create

create or replace force editionable view veranolink.view_sequence_create (
    project_id,
    contract_number,
    project_baseline_id,
    "HierarchyPathID",
    "CostObjectID",
    "CostObjectName",
    "ExternalID",
    "Hours",
    "StartDateOBCost",
    "EndDateOBCost",
    "Type",
    tipo_objeto,
    orden_jerarquico,
    updatedate_actual,
    payload_json
) as
    with
-- Linea base vigente del proyecto.
-- CURRENT manda sobre ORIGINAL. La ORIGINAL solo se usa si el proyecto
-- nunca ha consumido una CURRENT: una vez usada la CURRENT no se retrocede.
     bl_vigente as (
        select
            x.project_id,
            x.project_baseline_id,
            x.baseline_type
        from
            (
                select
                    b.project_id,
                    b.project_baseline_id,
                    b.baseline_type,
                    row_number()
                    over(partition by b.project_id
                         order by
                             case b.baseline_type
                                 when 'CURRENT' then
                                     1
                                 else
                                     2
                             end, b.baseline_time desc
                    ) as rn
                from
                    tbl_project_baseline b
                where
                        b.vigente = 'Y'
                    and ( b.baseline_type = 'CURRENT'
                          or not exists (
                        select
                            1
                        from
                            tbl_project_baseline c
                        where
                                c.project_id = b.project_id
                            and c.baseline_type = 'CURRENT'
                            and c.fecha_primer_consumo is not null
                    ) )
            ) x
        where
            x.rn = 1
    ),
-- Ultima carga de cada actividad dentro de su linea base
-- (un REINTENTO inserta una fila nueva para la misma actividad).
     act_bl as (
        select
            z.*
        from
            (
                select
                    a.*,
                    row_number()
                    over(partition by a.project_baseline_id, a.activity_id
                         order by
                             a.fecha_carga desc, a.id_fila desc
                    ) as rn
                from
                    tbl_activity_baseline a
            ) z
        where
            z.rn = 1
    )
-- =============== WBS ===============
    select
        w.project_id,
        p.contract_number,
        w.project_baseline_id,
        p.contract_number
        || substr(w.wbs_path,
                  instr(w.wbs_path, '.')) as "HierarchyPathID",
        w.wbs_code              as "CostObjectID",
        w.wbs_name              as "CostObjectName",
        to_char(w.wbs_id)       as "ExternalID",
        ''                      as "Hours",
        ''                      as "StartDateOBCost",
        ''                      as "EndDateOBCost",
        'WBS'                   as "Type",
        'WBS'                   as tipo_objeto,
        w.nivel                 as orden_jerarquico,
        w.updatedate            as updatedate_actual,
    -- Oracle trata '' como NULL dentro de JSON_OBJECT, por eso el marcador
    -- __EMPTY__ que luego se reemplaza por cadena vacia real.
        replace(
            json_object(
                'HierarchyPathID' value p.contract_number
                                        || substr(w.wbs_path,
                                                  instr(w.wbs_path, '.')),
                        'CostObjectID' value w.wbs_code,
                        'CostObjectName' value w.wbs_name,
                        'Hours' value '__EMPTY__',
                        'StartDateOBCost' value '__EMPTY__',
                        'EndDateOBCost' value '__EMPTY__',
                        'Type' value 'WBS',
                        'ExternalID' value to_char(w.wbs_id)
            ),
            '"__EMPTY__"',
            '""'
        )                       as payload_json
    from
             tbl_wbs_baseline w
        join tbl_project p on p.project_id = w.project_id
        join bl_vigente  bv on bv.project_id = w.project_id
                              and bv.project_baseline_id = w.project_baseline_id
    where
        not exists (
            select
                1
            from
                log_opc_sequence l
            where
                    l.tipo_objeto = 'WBS'
                and l.object_id = w.wbs_id
                and l.resultado = 'OK'
        )
    union all
-- =============== ACTIVIDAD ===============
-- Fechas congeladas de la linea base. En hitos (una sola fecha) se duplica
-- la faltante con NVL cruzado.
    select
        a.project_id,
        p.contract_number,
        a.project_baseline_id,
        p.contract_number
        || substr(wp.wbs_path,
                  instr(wp.wbs_path, '.'))
        || '.'
        || a.activity_code     as "HierarchyPathID",
        a.activity_code        as "CostObjectID",
        a.activity_name        as "CostObjectName",
        to_char(a.activity_id) as "ExternalID",
        nvl(
            to_char(a.planned_labor_units),
            ''
        )                      as "Hours",
        to_char(
            nvl(a.bl_start_date, a.bl_finish_date),
            'YYYY-MM-DD'
        )                      as "StartDateOBCost",
        to_char(
            nvl(a.bl_finish_date, a.bl_start_date),
            'YYYY-MM-DD'
        )                      as "EndDateOBCost",
        a.type                 as "Type",
        'ACTIVITY'             as tipo_objeto,
        9999                   as orden_jerarquico,
        a.updatedate           as updatedate_actual,
        replace(
            json_object(
                'HierarchyPathID' value p.contract_number
                                        || substr(wp.wbs_path,
                                                  instr(wp.wbs_path, '.'))
                                        || '.'
                                        || a.activity_code,
                        'CostObjectID' value a.activity_code,
                        'CostObjectName' value a.activity_name,
                        'Hours' value nvl(
                    to_char(a.planned_labor_units),
                    '__EMPTY__'
                ),
                        'StartDateOBCost' value to_char(
                    nvl(a.bl_start_date, a.bl_finish_date),
                    'YYYY-MM-DD'
                ),
                        'EndDateOBCost' value to_char(
                    nvl(a.bl_finish_date, a.bl_start_date),
                    'YYYY-MM-DD'
                ),
                        'Type' value a.type,
                        'ExternalID' value to_char(a.activity_id)
            ),
            '"__EMPTY__"',
            '""'
        )                      as payload_json
    from
             act_bl a
        join tbl_project      p on p.project_id = a.project_id
        join bl_vigente       bv on bv.project_id = a.project_id
                              and bv.project_baseline_id = a.project_baseline_id
        join tbl_wbs_baseline wp on wp.project_baseline_id = a.project_baseline_id
                                    and wp.wbs_id = a.wbs_id
    where
        not exists (
            select
                1
            from
                log_opc_sequence l
            where
                    l.tipo_objeto = 'ACTIVITY'
                and l.object_id = a.activity_id
                and l.resultado = 'OK'
        );

