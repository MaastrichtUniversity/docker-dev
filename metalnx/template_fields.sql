--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

SET search_path = public, pg_catalog;

--
-- Data for Name: template_fields; Type: TABLE DATA; Schema: public; Owner: metalnx
--

INSERT INTO template_fields (template_field_id, max_attr_length, max_unt_length, max_val_length, attribute, attribute_unit, attribute_value, end_range, field_order, start_range, template_id) VALUES (2, 100, 100, 100, 'title', '', '', 0, 0, 0, 2);
INSERT INTO template_fields (template_field_id, max_attr_length, max_unt_length, max_val_length, attribute, attribute_unit, attribute_value, end_range, field_order, start_range, template_id) VALUES (3, 100, 100, 100, 'resource', '', '', 0, 0, 0, 2);
INSERT INTO template_fields (template_field_id, max_attr_length, max_unt_length, max_val_length, attribute, attribute_unit, attribute_value, end_range, field_order, start_range, template_id) VALUES (4, 100, 100, 100, 'ingestResource', '', '', 0, 0, 0, 2);
INSERT INTO template_fields (template_field_id, max_attr_length, max_unt_length, max_val_length, attribute, attribute_unit, attribute_value, end_range, field_order, start_range, template_id) VALUES (5, 100, 100, 100, 'dataRetentionPeriodEndDate', '', '', 0, 0, 0, 2);
INSERT INTO template_fields (template_field_id, max_attr_length, max_unt_length, max_val_length, attribute, attribute_unit, attribute_value, end_range, field_order, start_range, template_id) VALUES (6, 100, 100, 100, 'storageQuotaGb', '', '', 0, 0, 0, 2);
INSERT INTO template_fields (template_field_id, max_attr_length, max_unt_length, max_val_length, attribute, attribute_unit, attribute_value, end_range, field_order, start_range, template_id) VALUES (7, 100, 100, 100, 'authorizationPeriodEndDate', '', '', 0, 0, 0, 2);

--
-- Name: template_fields_template_field_id_seq; Type: SEQUENCE SET; Schema: public; Owner: metalnx
--

SELECT pg_catalog.setval('template_fields_template_field_id_seq', 7, true);




--
-- PostgreSQL database dump complete
--

