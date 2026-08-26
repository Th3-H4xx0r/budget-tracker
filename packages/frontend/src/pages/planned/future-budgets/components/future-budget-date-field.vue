<script setup lang="ts">
import DateField from '@/components/fields/date-field.vue';
import { format } from 'date-fns';
import { computed } from 'vue';

const props = defineProps<{
  modelValue?: string | null;
  label?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  (event: 'update:modelValue', value: string): void;
}>();

const pickerValue = computed<Date | undefined>({
  get: () => (props.modelValue ? new Date(`${props.modelValue}T12:00:00`) : undefined),
  set: (value) => {
    if (value) emit('update:modelValue', format(value, 'yyyy-MM-dd'));
  },
});
</script>

<template>
  <DateField v-model="pickerValue" :label="label" :disabled="disabled" />
</template>
