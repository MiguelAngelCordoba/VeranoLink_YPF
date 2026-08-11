create or replace force editionable view veranolink.view_sequence_create (
    project_id,
    contract_number,
    "HierarchyPathID",
    "CostObjectID",
    "CostObjectName",
    "ExternalID",
    "Hours",
    "StartDateOBCost",
    "EndDateOBCost",
    "Type",
    tipo_objeto,
    updatedate_actual,
    payload_json
) as
    with wbs_ultimo as (
        select
            w.*
        from
            tbl_wbs w
        where
            w.updatedate = (
                select
                    max(w2.updatedate)
                from
                    tbl_wbs w2
                where
                    w2.wbs_id = w.wbs_id
            )
    ), act_ultimo as (
        select
            a.*
        from
            tbl_activity a
        where
            a.updatedate = (
                select
                    max(a2.updatedate)
                from
                    tbl_activity a2
                where
                    a2.activity_id = a.activity_id
            )
    )
-- =============== WBS ===============
    select
        w.project_id            as project_id,
        p.contract_number       as contract_number,
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
        w.updatedate            as updatedate_actual,
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
             wbs_ultimo w
        join tbl_project p on p.project_id = w.project_id
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
-- Fechas segun BASELINE:
--   CURRENT  -> se usan CURRENT_BL_START_DATE / CURRENT_BL_FINISH_DATE
--   ORIGINAL -> se usan ORIGINAL_BL_START_DATE / ORIGINAL_BL_FINISH_DATE
-- Se excluye BASELINE='SIN_LB' (no se envia a Sequence).
    select
        a.project_id           as project_id,
        p.contract_number      as contract_number,
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
        case a.baseline
            when 'CURRENT'  then
                to_char(a.current_bl_start_date, 'YYYY-MM-DD')
            when 'ORIGINAL' then
                to_char(a.original_bl_start_date, 'YYYY-MM-DD')
        end                    as "StartDateOBCost",
        case a.baseline
            when 'CURRENT'  then
                to_char(a.current_bl_finish_date, 'YYYY-MM-DD')
            when 'ORIGINAL' then
                to_char(a.original_bl_finish_date, 'YYYY-MM-DD')
        end                    as "EndDateOBCost",
        a.type                 as "Type",
        'ACTIVITY'             as tipo_objeto,
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
                        'StartDateOBCost' value
                    case a.baseline
                        when 'CURRENT'  then
                            to_char(a.current_bl_start_date, 'YYYY-MM-DD')
                        when 'ORIGINAL' then
                            to_char(a.original_bl_start_date, 'YYYY-MM-DD')
                    end,
                        'EndDateOBCost' value
                    case a.baseline
                        when 'CURRENT'  then
                            to_char(a.current_bl_finish_date, 'YYYY-MM-DD')
                        when 'ORIGINAL' then
                            to_char(a.original_bl_finish_date, 'YYYY-MM-DD')
                    end,
                        'Type' value a.type,
                        'ExternalID' value to_char(a.activity_id)
            ),
            '"__EMPTY__"',
            '""'
        )                      as payload_json
    from
             act_ultimo a
        join tbl_project p on p.project_id = a.project_id
        join wbs_ultimo  wp on wp.wbs_id = a.wbs_id
    where
        a.baseline in ( 'CURRENT', 'ORIGINAL' )
        and not exists (
            select
                1
            from
                log_opc_sequence l
            where
                    l.tipo_objeto = 'ACTIVITY'
                and l.object_id = a.activity_id
                and l.resultado = 'OK'
        );


-- sqlcl_snapshot {"hash":"a97c20859dd731a85d662f23967600d8730e2fbf","type":"VIEW","name":"VIEW_SEQUENCE_CREATE","schemaName":"VERANOLINK","sxml":""}