<template>
  <div v-if="setup" class="border-border @container/iphone-access rounded-lg border p-4">
    <div class="flex items-start justify-between gap-3">
      <div class="flex items-center gap-3">
        <div class="bg-muted flex size-10 shrink-0 items-center justify-center rounded-lg">
          <SmartphoneIcon class="text-muted-foreground size-5" />
        </div>
        <div>
          <p class="font-medium">{{ $t('settings.security.iphoneAccess.title') }}</p>
          <p class="text-muted-foreground text-sm">{{ $t('settings.security.iphoneAccess.description') }}</p>
        </div>
      </div>
      <Button variant="outline" size="sm" :aria-expanded="isRevealed" @click="isRevealed = !isRevealed">
        {{ isRevealed ? $t('settings.security.iphoneAccess.hide') : $t('settings.security.iphoneAccess.show') }}
      </Button>
    </div>

    <div v-if="isRevealed" class="mt-4 flex flex-col gap-4 border-t pt-4 @lg/iphone-access:flex-row">
      <div
        role="img"
        :aria-label="t('settings.security.iphoneAccess.qrLabel')"
        class="size-48 shrink-0 self-center overflow-hidden rounded-lg bg-white p-2 @lg/iphone-access:self-start"
      >
        <!-- eslint-disable-next-line vue/no-v-html -- SVG generated locally by uqr from the payload -->
        <div class="size-full [&>svg]:size-full" v-html="qrSvg" />
      </div>

      <div class="flex min-w-0 flex-1 flex-col gap-3">
        <div v-for="field in fields" :key="field.label">
          <p class="text-muted-foreground mb-1 text-xs">{{ field.label }}</p>
          <div class="bg-muted flex items-center gap-2 rounded-lg p-2">
            <code class="flex-1 truncate text-sm">{{ field.value }}</code>
            <DesktopOnlyTooltip :content="$t('settings.security.iphoneAccess.copy')">
              <Button
                variant="outline"
                size="icon-sm"
                :aria-label="$t('settings.security.iphoneAccess.copy')"
                @click="copyField({ value: field.value })"
              >
                <CheckIcon v-if="copied && copiedValue === field.value" class="size-4" />
                <CopyIcon v-else class="size-4" />
              </Button>
            </DesktopOnlyTooltip>
          </div>
        </div>

        <p class="text-warning-text text-sm">
          <AlertTriangleIcon class="mr-1 inline size-4" />
          {{ $t('settings.security.iphoneAccess.warning') }}
        </p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { getCloudflareAccessDeviceSetup } from '@/api/cloudflare-access';
import { VUE_QUERY_CACHE_KEYS } from '@/common/const';
import { Button } from '@/components/lib/ui/button';
import { DesktopOnlyTooltip } from '@/components/lib/ui/tooltip';
import { useIsAdmin } from '@/composable';
import { buildCloudflareAccessQrPayload } from '@/js/helpers/cloudflare-access-qr-payload';
import { AlertTriangleIcon, CheckIcon, CopyIcon, SmartphoneIcon } from '@lucide/vue';
import { useQuery } from '@tanstack/vue-query';
import { useClipboard } from '@vueuse/core';
import { renderSVG } from 'uqr';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const COPIED_RESET_MS = 2000;

const { t } = useI18n();
const { isAdmin } = useIsAdmin();

const { data: setup } = useQuery({
  queryKey: VUE_QUERY_CACHE_KEYS.cloudflareAccessDeviceSetup,
  queryFn: getCloudflareAccessDeviceSetup,
  enabled: isAdmin,
  // The secret is not kept in the cache once the card is gone.
  gcTime: 0,
});

const isRevealed = ref(false);

const qrSvg = computed(() => (setup.value ? renderSVG(buildCloudflareAccessQrPayload(setup.value)) : ''));

const fields = computed(() =>
  setup.value
    ? [
        { label: t('settings.security.iphoneAccess.clientId'), value: setup.value.clientId },
        { label: t('settings.security.iphoneAccess.clientSecret'), value: setup.value.clientSecret },
      ]
    : [],
);

const { copy, copied } = useClipboard({ copiedDuring: COPIED_RESET_MS });
const copiedValue = ref<string | null>(null);

const copyField = async ({ value }: { value: string }) => {
  await copy(value);
  copiedValue.value = copied.value ? value : null;
};
</script>
