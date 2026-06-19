@Component
export struct MessageComposer {
  @Prop draftMessage: string = '';
  @Prop isSendingMessage: boolean = false;
  @Prop sendErrorText: string = '';
  @Prop canSendMessage: boolean = false;
  @Prop placeholderText: ResourceStr = $r('app.string.message_composer_placeholder');
  onDraftChange: (value: string) => void = (_value: string): void => {};
  onClearError: () => void = (): void => {};
  onSendClick: () => void = (): void => {};

  build() {
    Column() {
      Column({ space: 5 }) {
        if (this.sendErrorText.length > 0) {
          Text(this.sendErrorText)
            .fontSize(9)
            .fontColor($r('app.color.message_composer_error_text'))
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .width('82%')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.message_composer_error_background'))
            .borderRadius(10)
        }

        TextArea({ text: this.draftMessage, placeholder: this.placeholderText })
          .onChange((value: string) => {
            this.onDraftChange(value);
            if (this.sendErrorText.length > 0) {
              this.onClearError();
            }
          })
          .width('85%')
          .height('90%')
          .fontSize(11)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.message_composer_placeholder_text'))
          .placeholderFont({ size: 8, weight: FontWeight.Regular })
          .enabled(!this.isSendingMessage)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.message_composer_input_background'))
          .borderRadius(16)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Button() {
        Image($r('app.media.chat_icon_send_white'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .enabled(this.canSendMessage)
      .backgroundColor(this.canSendMessage ? $r('app.color.surface_profile_chats_fill') : $r('app.color.button_disabled_secondary'))
      .opacity(this.canSendMessage ? 0.94 : 0.78)
      .shadow({
        color: $r('app.color.surface_elevation_shadow'),
        radius: 12,
        offsetX: 0,
        offsetY: 4
      })
      .onClick(() => {
        this.onSendClick();
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 8, right: 8, top: 8, bottom: 12 })
  }
}
