<script setup lang="ts">
import { cn } from '@/lib/utils';
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <tbody :class="cn('[&_tr:last-child]:border-0', attrs.class as string)">
    <slot />
  </tbody>
</template>
