-- Download my data (PRIV-01) is removed: on a phone, the file opened with no way back to FABA, and
-- the feature was dropped rather than fixed. This removes the export and the table that limited it
-- to three a day. Deleting an account (PROF-05) is unchanged.

DROP FUNCTION public.export_my_data();

DROP TABLE public.data_exports;
