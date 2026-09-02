# Enzo Care Tracking

Enzo Care Tracking records the small set of caregiving observations needed to understand feeding and diaper patterns.

## Language

**Event**:
A timestamped care record that is exactly one Feed or one Diaper.
_Avoid_: Entry, log item

**Feed**:
An Event recording milk offered to Enzo, including its milk type and optionally its completed volume.
_Avoid_: Eating event, bottle event

**Diaper**:
An Event containing independent Pee and Poop observations. At least one observation is present, and both may be present in the same Diaper.
_Avoid_: Pee event, Poop event, Both event

**Pee**:
A wet observation inside a Diaper.
_Avoid_: Wet event

**Poop**:
A dirty observation inside a Diaper.
_Avoid_: Dirty event

**Checkup**:
A dated clinician visit recording Enzo's weight and any goals the doctor changed. The latest past Checkup is the active care plan; any goal it leaves blank falls back to published Guidance.
_Avoid_: Appointment, override

**Guidance**:
The published age- and weight-based reference values (CDC, AAP, Safer Care Victoria, NHS) used for any goal no Checkup has set.
_Avoid_: Default, rule
