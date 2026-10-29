'use strict';

const CONTRACT_VERSION = '1.0';
const AGE_GROUPS = Object.freeze({
  '12_18': Object.freeze({ id: '12_18', label: '12–18 ay', minMonths: 12, maxMonths: 18, includesMax: false }),
  '18_24': Object.freeze({ id: '18_24', label: '18–24 ay', minMonths: 18, maxMonths: 24, includesMax: false }),
  '24_36': Object.freeze({ id: '24_36', label: '24–36 ay', minMonths: 24, maxMonths: 36, includesMax: true }),
});

function validateAgeGroup(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== 2 || value.contractVersion !== CONTRACT_VERSION ||
      typeof value.id !== 'string' || !Object.hasOwn(AGE_GROUPS, value.id)) return null;
  return Object.freeze({ contractVersion: CONTRACT_VERSION, id: value.id });
}

function fromLegacyMonths(months) {
  if (!Number.isInteger(months) || months < 12 || months > 36) return null;
  const match = Object.values(AGE_GROUPS).find(group => months >= group.minMonths &&
    (group.includesMax ? months <= group.maxMonths : months < group.maxMonths));
  return match ? Object.freeze({ contractVersion: CONTRACT_VERSION, id: match.id }) : null;
}

function describeAgeGroup(value) {
  const group = validateAgeGroup(value);
  return group ? AGE_GROUPS[group.id].label : null;
}

module.exports = { CONTRACT_VERSION, AGE_GROUPS, validateAgeGroup, fromLegacyMonths, describeAgeGroup };
