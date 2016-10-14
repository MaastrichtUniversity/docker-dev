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
-- Data for Name: templates; Type: TABLE DATA; Schema: public; Owner: metalnx
--

INSERT INTO templates (template_id, access_type, create_ts, description, ismodified, modify_ts, owner, template_name, usage_info, version) VALUES (2, 'system', '2016-10-14 08:43:06.047', 'Projects AVU''s', false, '2016-10-14 08:43:06.047', 'rods', 'Project', NULL, 1);


--
-- Name: templates_template_id_seq; Type: SEQUENCE SET; Schema: public; Owner: metalnx
--

SELECT pg_catalog.setval('templates_template_id_seq', 2, true);


--
-- PostgreSQL database dump complete
--

